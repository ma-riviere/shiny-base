suppressPackageStartupMessages({
    library(shiny)
    library(shinyutils)
    library(shiny.i18n)
    library(DT) # Avoid Global error: object 'datatables_html' not found
})

shinyutils::load_subfolders("R")

# ------ CONFIG ----------------------------------------------------------------

# Setup async processing for ExtendedTask (model fitting)
mirai::daemons(max(parallelly::availableCores() - 1, 1))

options(
    # Auth0
    auth0_disable = isTRUE(getOption("shiny.testmode")) || isTRUE(as.logical(Sys.getenv("BYPASS_AUTH0", "FALSE"))),

    # Database
    db_path_dev = "database/dev.db",

    # Sessions
    session_timeout_minutes = 15,

    # Bookmarks
    bookmark_dir = Sys.getenv("BOOKMARK_DIR", "shiny_bookmarks"),
    bookmark_expiry_minutes = 30,

    # i18n (shinyutils::init_i18n merges pkg + app translations)
    language_cookie_name = "user_language",
    language_cookie_expiration = 525600, # 1 year in minutes
    default_language = "en",

    # Logging (see shinyutils package for LOG_* constants)
    # Levels: LOG_OFF=0, LOG_FATAL=100, LOG_ERROR=200, LOG_WARN=300, LOG_INFO=400, LOG_DEBUG=500, LOG_TRACE=600
    log_dir = Sys.getenv("LOGS_DIR", "logs"),
    log_console_threshold = if (Sys.getenv("ENV") == "prod") 400L else 500L, # INFO in prod, DEBUG in dev
    log_file_threshold = 500L, # DEBUG

    # Email (see shinyutils::send_error_email for usage)
    email_to = Sys.getenv("EMAIL_TO"),
    email_from = Sys.getenv("EMAIL_FROM", "noreply@app.local"),
    smtp_host = Sys.getenv("SMTP_HOST"),
    smtp_port = as.integer(Sys.getenv("SMTP_PORT", "587")),
    smtp_user = Sys.getenv("SMTP_USER"),
    smtp_key_envvar = "SMTP_KEY",

    # Error handling (see shinyutils::setup_global_error_emails)
    error_email_enabled = isTRUE(as.logical(Sys.getenv("SEND_ERROR_EMAILS", "FALSE"))),

    # Caching (see shinyutils::cache_memory, shinyutils::cache_disk)
    cache_dir = "cache",

    # Auth0 RBAC (see shinyutils::can, shinyutils::load_permissions_config)
    # Must match the namespace in your Auth0 Action that adds roles to the ID token
    auth0_roles_claim = "https://shiny-base.ma-riviere.com/roles",
    permissions_file = "data/permissions.yaml",

    # Debug
    # DISABLED: autoreload was causing app restarts during E2E tests (file writes to bookmarks/logs)
    shiny.autoreload = FALSE,
    shiny.autoreload.pattern = "\\.(R|css|scss|js|html?|json|ya?ml)$"
)

# ------ CSS -------------------------------------------------------------------

shinyutils::compile_sass() # Defaults: www/sass/main.scss -> www/css/main.min.css

# ------ LOGGING ---------------------------------------------------------------
# Initialize logging early so it's available for all subsequent initialization

shinyutils::init_logging()
shinyutils::setup_global_error_emails()

# ------ AUTH0 -----------------------------------------------------------------

# Will return NULL if auth0 is disabled (e.g. auth0_disable = TRUE or BYPASS_AUTH0 = TRUE)
auth0_mgmt <- shinyutils::init_auth0()

auth0_info <- if (isTRUE(getOption("auth0_disable"))) NULL else auth0r::auth0_info()

# ------ DATABASE --------------------------------------------------------------

db_pool <- shinyutils::db_connect()

# Clean up guest users (and their linked records via CASCADE) on startup.
# Guest users are created during tests when Auth0 is bypassed.
shinyutils::db_delete_guest_users()

# ------ OTEL ------------------------------------------------------------------

shinyutils::init_otel()

# ------ I18N ------------------------------------------------------------------

i18n <- shinyutils::init_i18n("data/translations.json")

# ------ BOOKMARKS -------------------------------------------------------------

enableBookmarking(store = "server")

# Run cleanup on startup
shinyutils::bookmark_cleanup()
# Schedule recurring cleanup every 30 minutes
shinyutils::schedule_task("bookmark_cleanup", shinyutils::bookmark_cleanup, interval_seconds = 30 * 60)

# ------ SESSIONS --------------------------------------------------------------

# Session cleanup: mark stale sessions (no heartbeat for 15+ min) as timed out
# Runs every 10 minutes. Heartbeat is every 5 min, so 15 min = 3 missed heartbeats.
shinyutils::schedule_task("session_cleanup", shinyutils::session_cleanup, interval_seconds = 10 * 60)

# ------ LOGS ------------------------------------------------------------------

# Run logs cleanup on startup only (logs are only created on app start)
shinyutils::logs_cleanup()

# ------ CLEANING --------------------------------------------------------------

shinyutils::register_on_stop(
    function() {
        shinyutils::cancel_all_tasks()
        shinyutils::clear_disk_cache(getOption("cache_dir", "cache"))
        shinyutils::db_disconnect()
    },
    id = "cleanup"
)

# ------------------------------------------------------------------------------

shinyutils::log_info("Application started (ENV={Sys.getenv('ENV', 'dev')})")
