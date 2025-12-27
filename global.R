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
    error_email_enabled = isTRUE(as.logical(Sys.getenv("SEND_ERROR_EMAILS", "FALSE"))),

    # Caching (see R/shiny-utils/caching.R)
    cache_dir = "cache",

    # Auth0 RBAC (see R/shiny-utils/auth.R)
    # Must match the namespace in your Auth0 Action that adds roles to the ID token
    auth0_roles_claim = "https://shiny-base.ma-riviere.com/roles",

    # Debug
    shiny.autoreload = if (is_prod) FALSE else TRUE
)

enableBookmarking(store = "server")

# ------ SUB-DIRS --------------------------------------------------------------
# Sourcing R files from all sub-directories in R/
# Load shiny-utils first (contains logging, database, etc.), then other directories
if (dir.exists("R/shiny-utils/")) {
    void_ <- lapply(
        list.files(path = "R/shiny-utils/", pattern = "\\.[Rr]$", full.names = TRUE, recursive = TRUE),
        source
    )
}

void_ <- lapply(
    {
        r_subdirs <- list.dirs("R", full.names = TRUE, recursive = FALSE)
        r_subdirs[basename(r_subdirs) != "shiny-utils"]
    },
    \(d) lapply(list.files(path = d, pattern = "\\.[Rr]$", full.names = TRUE, recursive = TRUE), source)
)

# ------ LOGGING ---------------------------------------------------------------
# Initialize logging early so it's available for all subsequent initialization

init_logging()
setup_global_error_handlers()

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

db_pool <- db_connect()

onStop(function() {
    cancel_all_tasks()
    clear_disk_cache(getOption("cache_dir", "cache"))
    db_disconnect(db_pool)
})

# ------ BOOKMARKS -------------------------------------------------------------
# The database/pool needs to be active to be able to call bookmark_cleanup

source("R/helpers_bookmarks.R", local = TRUE)
source("R/helpers_database.R", local = TRUE)

# Run cleanup on startup, then schedule recurring cleanup every 30 minutes
bookmark_cleanup()
schedule_task(
    "bookmark_cleanup",
    bookmark_cleanup,
    interval_seconds = 30 * 60 # In minutes
)

# Run logs cleanup on startup only (logs are only created on app start)
logs_cleanup()

log_info("Application started (ENV={Sys.getenv('ENV', 'dev')})")
