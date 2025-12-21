suppressPackageStartupMessages({
    library(shiny)
    library(shiny.i18n)
})

# ------ CONFIG ----------------------------------------------------------------

is_prod <- Sys.getenv("ENV") == "prod"

options(
    # Database
    db_schema_path = "database/schema.sql",
    db_path_dev = "database/dev.db",

    # Bookmarks
    bookmark_dir = "shiny_bookmarks",
    bookmark_expiry_minutes = 30,

    # i18n
    i18n_file_path = "data/translations.json",
    language_cookie_name = "user_language",
    language_cookie_expiration = 525600, # 1 year in minutes
    default_language = "en",

    # Logging (see R/shiny-utils/logging.R)
    log_dir = Sys.getenv("LOGS_DIR", "logs"),
    log_console_threshold = if (is_prod) logger::INFO else logger::DEBUG,
    log_file_threshold = logger::DEBUG,
    log_json_format = is_prod,

    # Email (see R/shiny-utils/error_handling.R for error email usage)
    email_to = Sys.getenv("EMAIL_TO"),
    email_from = Sys.getenv("EMAIL_FROM", "noreply@app.local"),
    smtp_host = Sys.getenv("SMTP_HOST"),
    smtp_port = as.integer(Sys.getenv("SMTP_PORT", "587")),
    smtp_user = Sys.getenv("SMTP_USER"),
    smtp_key_envvar = "SMTP_KEY",

    # Error handling (see R/shiny-utils/error_handling.R)
    error_email_enabled = is_prod && nzchar(Sys.getenv("EMAIL_TO")),

    # Shinylogs
    shinylogs_dir = Sys.getenv("SHINYLOGS_DIR", "data/shinylogs"),

    # Caching (see R/shiny-utils/caching.R)
    cache_dir = "cache",

    # Debug
    shiny.autoreload = if (is_prod) FALSE else TRUE
)

enableBookmarking(store = "server")

# ------ SUB-DIRS --------------------------------------------------------------
# Sourcing R files from all sub-directories in R/
void_ <- lapply(
    list.dirs("R", full.names = TRUE, recursive = FALSE),
    \(d) lapply(list.files(path = d, pattern = "\\.[Rr]$", full.names = TRUE, recursive = TRUE), source)
)

# ------ AUTH0 -----------------------------------------------------------------
# Set options(auth0_disable = TRUE) to skip auth during development
if (isTRUE(getOption("shiny.testmode"))) {
    options(auth0_disable = TRUE)
}

auth0_info <- auth0r::auth0_info()
auth0_mgmt <- if (!isTRUE(getOption("auth0_disable"))) {
    auth0r::Auth0Management$new()
} else {
    NULL
}

# ------ TRANSLATIONS ----------------------------------------------------------

i18n <- shiny.i18n::Translator$new(translation_json_path = getOption("i18n_file_path", "data/translations.json"))
i18n$set_translation_language("en")

# ------ DATABASE --------------------------------------------------------------

pool <- db_connect()

onStop(function() {
    clear_disk_cache(getOption("cache_dir", "cache"))
    db_disconnect(pool)
})

# ------ BOOKMARKS -------------------------------------------------------------
# The database/pool needs to be active to be able to call bookmark_cleanup

source("R/helpers_bookmarks.R", local = TRUE)
source("R/helpers_database.R", local = TRUE)

bookmark_cleanup(pool)

# ------ LOGGING ---------------------------------------------------------------

init_logging()
setup_global_error_handlers()

log_info("Application started (ENV={Sys.getenv('ENV', 'dev')})")

# ------ SHINYLOGS -------------------------------------------------------------
# Ensure shinylogs directory exists

shinylogs_dir <- getOption("shinylogs_dir")
if (!dir.exists(shinylogs_dir)) {
    dir.create(shinylogs_dir, recursive = TRUE)
}
