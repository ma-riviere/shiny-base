# Runs before Shiny Server starts (Dockerfile CMD), in production only.
# Check writable folders -> connect to Postgres -> check schemas -> apply SQL files -> verify tables/columns.
# Any error stops the container. The HEAD healthcheck only checks Shiny Server, so it cannot replace these checks.
#
# DDL = Data Definition Language: SQL that creates/changes tables, indexes, constraints, etc.
# A Postgres schema groups tables: "shared" holds data used by both this app and plumber2-base;
# the app's own schema holds its sessions and bookmarks.

log <- function(msg) cat(sprintf("[prestart] %s\n", msg), file = stderr())

if (!identical(Sys.getenv("ENV"), "prod")) {
    log("ENV != prod: skipping prestart checks")
    quit(save = "no", status = 0)
}

app_root <- "/srv/shiny-server"
shared_schema <- "shared"

# Keep shared and app-private files separate. Loading every .sql file in both phases would create
# copies of the shared tables in the app schema, where queries would find them before the shared originals.
shared_ddl_file <- file.path(app_root, "database", "postgres", "schema-shared.sql")
private_ddl_files <- file.path(app_root, "database", "postgres", "schema-base.sql")

# CREATE TABLE IF NOT EXISTS leaves an existing table unchanged; new columns need explicit ALTER TABLE statements.
# Check the required shared columns after applying SQL, so missing columns stop startup before app queries fail.
# This checks column names only, not types or constraints. For private tables, we only check that they exist.
shared_expected_columns <- list(
    users = c("id", "auth0_sub", "email", "nickname", "is_guest", "created_at", "last_seen_at", "status"),
    datasets = c("id", "user_id", "name", "description", "data", "n_rows", "n_cols", "created_at", "updated_at"),
    models = c("id", "user_id", "dataset_id", "formula", "metrics", "model_blob", "created_at", "updated_at")
)
private_expected_tables <- c("sessions", "bookmarks")

# These files contain simple statements separated by semicolons. This is not a general SQL parser:
# no semicolons inside quoted strings or function bodies. Full-line SQL comments are removed before splitting.
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

# Check mounted folders as the container user (shiny). Missing folders or wrong permissions stop startup.
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

# Connection settings come from the platform's db.env (PGHOST, PGPORT, etc.); POSTGRES_* names are fallbacks.
con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("PGHOST", Sys.getenv("POSTGRES_HOST")),
    port = as.integer(Sys.getenv("PGPORT", Sys.getenv("POSTGRES_PORT", "5432"))),
    dbname = Sys.getenv("PGDATABASE", Sys.getenv("POSTGRES_DB")),
    user = Sys.getenv("PGUSER", Sys.getenv("POSTGRES_USER")),
    password = Sys.getenv("PGPASSWORD", Sys.getenv("POSTGRES_PASSWORD"))
)

# ------ CHECK SCHEMAS ---------------------------------------------------------
# search_path tells Postgres where to find tables: app schema first, then shared.
# If the app schema is missing/inaccessible, Postgres can silently use shared instead.
# The platform gives the app's DB role and schema the same name; check that we reached the expected schema.
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

# Reject app-local copies of users/datasets/models: queries would read those before the shared tables.
# Otherwise, both apps could appear to work while reading/writing different data.
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

# ------ APPLY SHARED SQL ------------------------------------------------------
# Both apps use the same advisory lock: only one can apply shared SQL at a time.
# The transaction applies this file as one unit and releases the lock when it ends.
# SET LOCAL ROLE makes new objects belong to the shared role, whichever app creates them.
# SET LOCAL search_path puts them in the shared schema. Both settings reset when the transaction ends.
DBI::dbBegin(con)
DBI::dbGetQuery(con, "SELECT pg_advisory_xact_lock(hashtext('shared_ddl')::bigint)")
DBI::dbExecute(con, sprintf('SET LOCAL ROLE "%s"', shared_schema))
DBI::dbExecute(con, sprintf('SET LOCAL search_path TO "%s"', shared_schema))
apply_ddl(con, shared_ddl_file)
DBI::dbCommit(con)

# Verify after committing. A failed check stops startup, but does not undo the committed schema changes.
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

# ------ APPLY APP-PRIVATE SQL -------------------------------------------------
# The original role/search_path are restored: tables now go in the app schema.
# A separate transaction and per-app lock prevent two starts of THIS app from applying private SQL together.
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
