# Prestart gate for the deploy-server platform, chained before shiny-server in
# the Dockerfile CMD. Any failure exits non-zero, the container stops, and
# `docker compose up --wait` fails the rollout instead of shipping a broken app
# (the shiny-server HEAD healthcheck alone cannot tell that R never booted).
# Steps: verify the bind-mounted state dirs are writable -> connect to Postgres
# -> apply database/postgres/schema*.sql (idempotent DDL, serialized across
# concurrent starts with an advisory lock) -> verify the expected tables exist.

log <- function(msg) cat(sprintf("[prestart] %s\n", msg), file = stderr())

if (!identical(Sys.getenv("ENV"), "prod")) {
    log("ENV != prod: skipping prestart checks")
    quit(save = "no", status = 0)
}

app_root <- "/srv/shiny-server"

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

app_schema <- DBI::dbGetQuery(con, "SELECT current_schema() AS schema")$schema
if (is.na(app_schema)) {
    stop("current_schema() is NULL: the DB role has no usable search_path (app schema missing or not owned)")
}
log(sprintf("Connected to '%s' as '%s' (schema: %s)", Sys.getenv("PGDATABASE"), Sys.getenv("PGUSER"), app_schema))

# Unqualified DDL lands in the role's pinned search_path schema. The advisory
# lock serializes DDL across concurrent container/R-process starts.
DBI::dbBegin(con)
DBI::dbGetQuery(con, "SELECT pg_advisory_xact_lock(hashtext(current_schema())::bigint)")

schema_files <- sort(list.files(
    file.path(app_root, "database", "postgres"),
    pattern = "^schema.*\\.sql$",
    full.names = TRUE
))
if (length(schema_files) == 0) {
    stop("No schema files found in database/postgres/")
}
for (schema_file in schema_files) {
    lines <- readLines(schema_file, warn = FALSE)
    lines <- lines[!startsWith(trimws(lines), "--")]
    statements <- strsplit(paste(lines, collapse = "\n"), ";", fixed = TRUE)[[1]]
    statements <- trimws(statements)
    statements <- statements[nzchar(statements)]
    for (statement in statements) {
        DBI::dbExecute(con, statement)
    }
    log(sprintf("Applied %s (%d statements)", basename(schema_file), length(statements)))
}
DBI::dbCommit(con)

expected_tables <- c("users", "sessions", "bookmarks", "datasets", "models")
existing_tables <- DBI::dbGetQuery(
    con,
    "SELECT table_name FROM information_schema.tables WHERE table_schema = current_schema()"
)$table_name
missing_tables <- setdiff(expected_tables, existing_tables)
if (length(missing_tables) > 0) {
    stop(sprintf("Missing table(s) after schema application: %s", paste(missing_tables, collapse = ", ")))
}

DBI::dbDisconnect(con)
log("OK: state dirs writable, schema in place")
