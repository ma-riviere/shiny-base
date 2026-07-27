# Prestart gate for the deploy-server platform, chained before shiny-server in
# the Dockerfile CMD. Any failure exits non-zero, the container stops, and
# `docker compose up --wait` fails the rollout instead of shipping a broken app
# (the shiny-server HEAD healthcheck alone cannot tell that R never booted).
# Steps: verify the bind-mounted state dirs are writable -> connect to Postgres
# -> assert schema sanity -> apply the shared cross-app DDL (schema "shared",
# owned by the NOLOGIN role "shared", serialized across BOTH apps with a common
# advisory lock) -> apply the app-private DDL -> verify the expected tables.

log <- function(msg) cat(sprintf("[prestart] %s\n", msg), file = stderr())

if (!identical(Sys.getenv("ENV"), "prod")) {
    log("ENV != prod: skipping prestart checks")
    quit(save = "no", status = 0)
}

app_root <- "/srv/shiny-server"
shared_schema <- "shared"

# Explicit file lists per phase: a glob would re-run schema-shared.sql in the
# private phase, where unqualified CREATEs land in the app schema and shadow
# the shared tables.
shared_ddl_file <- file.path(app_root, "database", "postgres", "schema-shared.sql")
private_ddl_files <- file.path(app_root, "database", "postgres", "schema-base.sql")

# Post-apply contract check: CREATE IF NOT EXISTS never evolves an existing
# table, so a column added in one repo but not yet applied here must fail the
# deploy loudly instead of surfacing as runtime SQL errors.
shared_expected_columns <- list(
    users = c("id", "auth0_sub", "email", "nickname", "is_guest", "created_at", "last_seen_at", "status"),
    datasets = c("id", "user_id", "name", "description", "data", "n_rows", "n_cols", "created_at", "updated_at"),
    models = c("id", "user_id", "dataset_id", "formula", "metrics", "model_blob", "created_at", "updated_at")
)
private_expected_tables <- c("sessions", "bookmarks")

read_statements <- function(path) {
    lines <- readLines(path, warn = FALSE)
    lines <- lines[!startsWith(trimws(lines), "--")]
    statements <- strsplit(paste(lines, collapse = "\n"), ";", fixed = TRUE)[[1]]
    statements <- trimws(statements)
    return(statements[nzchar(statements)])
}

apply_ddl <- function(con, path) {
    statements <- read_statements(path)
    for (statement in statements) {
        DBI::dbExecute(con, statement)
    }
    log(sprintf("Applied %s (%d statements)", basename(path), length(statements)))
}

state_dirs <- c(
    Sys.getenv("BOOKMARK_DIR", file.path(app_root, "shiny_bookmarks")),
    Sys.getenv("LOGS_DIR", "/var/log/shiny-server"),
    file.path(app_root, "shinylogs")
)
not_writable <- state_dirs[file.access(state_dirs, mode = 2) != 0L]
if (length(not_writable) > 0) {
    stop(sprintf(
        "State dir(s) missing or not writable by the container user: %s",
        paste(not_writable, collapse = ", ")
    ))
}

# libpq-style PG* vars come from the platform db.env; POSTGRES_* kept as fallback
con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("PGHOST", Sys.getenv("POSTGRES_HOST")),
    port = as.integer(Sys.getenv("PGPORT", Sys.getenv("POSTGRES_PORT", "5432"))),
    dbname = Sys.getenv("PGDATABASE", Sys.getenv("POSTGRES_DB")),
    user = Sys.getenv("PGUSER", Sys.getenv("POSTGRES_USER")),
    password = Sys.getenv("PGPASSWORD", Sys.getenv("POSTGRES_PASSWORD"))
)

# --- Phase 0: schema sanity -------------------------------------------------
# With search_path = "<app>", shared, a missing app schema makes
# current_schema() silently fall through to "shared". Role name == app schema
# name on this platform, so this catches both a NULL and a wrong resolution.
sanity <- DBI::dbGetQuery(con, "SELECT current_schema() AS schema, current_user AS role")
app_schema <- sanity$schema
if (is.na(app_schema) || !identical(app_schema, sanity$role)) {
    stop(sprintf(
        "current_schema() is '%s' but the role is '%s': app schema missing from search_path or not owned",
        app_schema,
        sanity$role
    ))
}
log(sprintf("Connected to '%s' as '%s' (schema: %s)", Sys.getenv("PGDATABASE"), Sys.getenv("PGUSER"), app_schema))

# Legacy/rollback guard: app-local copies of the shared tables would shadow
# shared.* for every unqualified query. Refuse to start until they are dropped
# (cutover step), rather than silently splitting data across two schemas.
shadow_tables <- DBI::dbGetQuery(
    con,
    sprintf(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_name IN (%s)",
        paste(sprintf("'%s'", names(shared_expected_columns)), collapse = ", ")
    ),
    params = list(app_schema)
)$table_name
if (length(shadow_tables) > 0) {
    stop(sprintf(
        "Shared-lineage table(s) still exist in app schema '%s' and would shadow the shared ones: %s",
        app_schema,
        paste(shadow_tables, collapse = ", ")
    ))
}

# --- Phase 1: shared cross-app DDL ------------------------------------------
# Common lock key across ALL apps applying the shared DDL. SET LOCAL ROLE makes
# the shared role own every object regardless of which app creates it first
# (membership granted by the platform); SET LOCAL search_path makes the
# unqualified DDL land in the shared schema instead of the app schema.
DBI::dbBegin(con)
DBI::dbGetQuery(con, "SELECT pg_advisory_xact_lock(hashtext('shared_ddl')::bigint)")
DBI::dbExecute(con, sprintf('SET LOCAL ROLE "%s"', shared_schema))
DBI::dbExecute(con, sprintf('SET LOCAL search_path TO "%s"', shared_schema))
apply_ddl(con, shared_ddl_file)
DBI::dbCommit(con)

shared_columns <- DBI::dbGetQuery(
    con,
    "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = $1",
    params = list(shared_schema)
)
for (table in names(shared_expected_columns)) {
    have <- shared_columns$column_name[shared_columns$table_name == table]
    missing <- setdiff(shared_expected_columns[[table]], have)
    if (length(missing) > 0) {
        stop(sprintf(
            "Shared table '%s.%s' is missing column(s): %s (schema-shared.sql drifted from the app code?)",
            shared_schema,
            table,
            paste(missing, collapse = ", ")
        ))
    }
}

# --- Phase 2: app-private DDL ------------------------------------------------
# Unqualified DDL lands in the app schema (first in search_path). Per-app lock:
# only concurrent starts of THIS app compete here.
DBI::dbBegin(con)
DBI::dbGetQuery(con, "SELECT pg_advisory_xact_lock(hashtext($1)::bigint)", params = list(app_schema))
for (ddl_file in private_ddl_files) {
    apply_ddl(con, ddl_file)
}
DBI::dbCommit(con)

existing_tables <- DBI::dbGetQuery(
    con,
    "SELECT table_name FROM information_schema.tables WHERE table_schema = $1",
    params = list(app_schema)
)$table_name
missing_tables <- setdiff(private_expected_tables, existing_tables)
if (length(missing_tables) > 0) {
    stop(sprintf("Missing table(s) after schema application: %s", paste(missing_tables, collapse = ", ")))
}

DBI::dbDisconnect(con)
log("OK: state dirs writable, shared and app schemas in place")
