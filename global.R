suppressPackageStartupMessages({
    library(shiny)
    library(shiny.i18n)
})

# ------ CONFIG ----------------------------------------------------------------

BOOKMARK_DIR <- "shiny_bookmarks"
BOOKMARK_EXPIRY_MINUTES <- 30

LANGUAGE_COOKIE_NAME <- "user_language"
LANGUAGE_COOKIE_EXPIRATION <- 525600 # 1 year in minutes
DEFAULT_LANGUAGE <- "en"

# ------------------------------------------------------------------------------

enableBookmarking(store = "server")

if (Sys.getenv("ENV") == "dev") {
    # Add 'watcher' to dev packages
    options(shiny.autoreload = TRUE)
}

# ------ AUTH0 -----------------------------------------------------------------
# Set options(auth0_disable = TRUE) to skip auth during development
if (isTRUE(getOption("shiny.testmode"))) {
    options(auth0_disable = TRUE)
}

auth0_info <- auth0::auth0_info()

# ------ DATABASE --------------------------------------------------------------

source("R/helpers_database.R", local = TRUE)
source("R/helpers_bookmarks.R", local = TRUE)

pool <- db_connect()

bookmark_cleanup(pool)

onStop(function() {
    Sys.sleep(0.5) # Allow reactive contexts to complete

    tryCatch(
        {
            pool::poolClose(pool)
            cat("Pool closed successfully\n", file = stderr())
        },
        error = function(e) {
            cat("Error closing pool:", e$message, "\n", file = stderr())
        }
    )
})
