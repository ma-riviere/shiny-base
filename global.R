suppressPackageStartupMessages({
    library(shiny)
    library(shiny.i18n)
    library(DT) # Avoid Global error: object 'datatables_html' not found
})

# Setup async processing for ExtendedTask (model fitting)
mirai::daemons(2)

# ------ CONFIG ----------------------------------------------------------------

is_prod <- Sys.getenv("ENV") == "prod"

options(
    # Database
    db_path_dev = "database/dev.db",

    # Sessions
    session_timeout_minutes = 15,

    # Bookmarks
    bookmark_dir = "shiny_bookmarks",
    bookmark_expiry_minutes = 30,

    # i18n
    i18n_file_path = "data/translations.json",
    language_cookie_name = "user_language",
    language_cookie_expiration = 525600, # 1 year in minutes
    default_language = "en",

    # Logging (see R/shiny-utils/logging.R for LOG_* constants)
    # Levels: LOG_OFF=0, LOG_FATAL=100, LOG_ERROR=200, LOG_WARN=300, LOG_INFO=400, LOG_DEBUG=500, LOG_TRACE=600
    log_dir = Sys.getenv("LOGS_DIR", "logs"),
    log_console_threshold = if (is_prod) 400L else 500L, # INFO in prod, DEBUG in dev
    log_file_threshold = 500L, # DEBUG

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

    # Auth0 RBAC (see R/shiny-utils/permissions.R)
    # Must match the namespace in your Auth0 Action that adds roles to the ID token
    auth0_roles_claim = "https://shiny-base.ma-riviere.com/roles",
    permissions_file = "data/permissions.yaml",

    # Debug
    shiny.autoreload = if (is_prod) FALSE else TRUE
)

enableBookmarking(store = "server")

# ------ SHINY-UTILS -----------------------------------------------------------

source(here::here("R", "shiny-utils", "init.R"))

load_subfolders("R")

# ------ LOGGING ---------------------------------------------------------------
# Initialize logging early so it's available for all subsequent initialization

init_logging()
setup_global_error_emails()

# ------ OTEL ------------------------------------------------------------------
# Memory-based trace storage for admin trace viewer
# Configured via .Renviron: OTEL_TRACES_EXPORTER=otelsdk::tracer_provider_memory
OTEL_TRACER_PROVIDER <- otel_setup_tracer()
OTEL_ENABLED <- !is.null(OTEL_TRACER_PROVIDER)
if (isTRUE(OTEL_ENABLED)) {
    log_info("[OTEL] Tracer initialized (provider: memory)")
}

# ------ AUTH0 -----------------------------------------------------------------
# Set options(auth0_disable = TRUE) to skip auth during development
if (isTRUE(getOption("shiny.testmode"))) {
    options(auth0_disable = TRUE)
}

auth0_info <- auth0r::auth0_info()
auth0_mgmt <- if (!isTRUE(getOption("auth0_disable"))) auth0r::Auth0Management$new() else NULL

# ------ TRANSLATIONS ----------------------------------------------------------

i18n <- shiny.i18n::Translator$new(translation_json_path = getOption("i18n_file_path", "data/translations.json"))
i18n$set_translation_language("en")

# ------ DATABASE --------------------------------------------------------------

db_pool <- db_connect()

register_on_stop(
    function() {
        cancel_all_tasks()
        clear_disk_cache(getOption("cache_dir", "cache"))
        db_disconnect(db_pool)
    },
    id = "cleanup"
)

# ------ BOOKMARKS -------------------------------------------------------------
# Put after the DATABASE section: the pool needs to be active to be able to call bookmark_cleanup

# Run cleanup on startup
bookmark_cleanup()

# Schedule recurring cleanup every 30 minutes
schedule_task("bookmark_cleanup", bookmark_cleanup, interval_seconds = 30 * 60)

# ------ SESSIONS --------------------------------------------------------------

# Session cleanup: mark stale sessions (no heartbeat for 15+ min) as timed out
# Runs every 10 minutes. Heartbeat is every 5 min, so 15 min = 3 missed heartbeats.
schedule_task("session_cleanup", session_cleanup, interval_seconds = 10 * 60)

# ------ LOGS ------------------------------------------------------------------

# Run logs cleanup on startup only (logs are only created on app start)
logs_cleanup()

log_info("Application started (ENV={Sys.getenv('ENV', 'dev')})")
