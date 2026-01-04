suppressPackageStartupMessages({
    library(shiny)
    library(shinyutils)
    library(shiny.i18n)
    library(DT) # Avoid Global error: object 'datatables_html' not found
})

# Setup async processing for ExtendedTask (model fitting)
mirai::daemons(2)

# ------ CONFIG ----------------------------------------------------------------

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

enableBookmarking(store = "server")

shinyutils::load_subfolders("R")

# ------ LOGGING ---------------------------------------------------------------
# Initialize logging early so it's available for all subsequent initialization

shinyutils::init_logging()
shinyutils::setup_global_error_emails()

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

db_pool <- shinyutils::db_connect()

# Configure shinyutils package resources (must be after db_pool, i18n, auth0_mgmt are created)
# OTel configured via .Renviron (e.g. OTEL_TRACES_EXPORTER=otelsdk::tracer_provider_memory)
shinyutils::set_shinyutils_resources(pool = db_pool, i18n = i18n, auth0_mgmt = auth0_mgmt, otel = TRUE)

shinyutils::register_on_stop(
    function() {
        shinyutils::cancel_all_tasks()
        shinyutils::clear_disk_cache(getOption("cache_dir", "cache"))
        shinyutils::db_disconnect(db_pool)
    },
    id = "cleanup"
)

# ------ BOOKMARKS -------------------------------------------------------------

# Run cleanup on startup
shinyutils::bookmark_cleanup()

# Schedule recurring cleanup every 30 minutes
shinyutils::schedule_task("bookmark_cleanup", shinyutils::bookmark_cleanup, interval_seconds = 30 * 60)

# ------ SESSIONS --------------------------------------------------------------

# Session cleanup: mark stale sessions (no heartbeat for 15+ min) as timed out
# Runs every 10 minutes. Heartbeat is every 5 min, so 15 min = 3 missed heartbeats.
shinyutils::schedule_task("session_cleanup", shinyutils::session_cleanup, interval_seconds = 10 * 60)

# ------ GUEST USERS -----------------------------------------------------------

# Clean up guest users (and their linked records via CASCADE) on startup.
# Guest users are created during tests when Auth0 is bypassed.
shinyutils::db_delete_guest_users()

# ------ LOGS ------------------------------------------------------------------

# Run logs cleanup on startup only (logs are only created on app start)
shinyutils::logs_cleanup()

shinyutils::log_info("Application started (ENV={Sys.getenv('ENV', 'dev')})")
