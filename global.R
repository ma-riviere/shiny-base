suppressPackageStartupMessages({
    library(shiny)
    library(shiny.i18n)
})

# ------ CONFIG ----------------------------------------------------------------

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
    default_language = "en"
)

enableBookmarking(store = "server")

if (Sys.getenv("ENV") == "dev") {
    # Add 'watcher' to dev packages
    options(shiny.autoreload = TRUE)
}

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

auth0_info <- auth0::auth0_info()

# ------ TRANSLATIONS ----------------------------------------------------------

i18n <- shiny.i18n::Translator$new(translation_json_path = getOption("i18n_file_path", "data/translations.json"))
i18n$set_translation_language("en")

# ------ DATABASE --------------------------------------------------------------

source("R/helpers_database.R", local = TRUE)

pool <- db_connect()

onStop(db_disconnect(pool))

# ------ BOOKMARKS -------------------------------------------------------------
# The database/pool needs to be active to be able to call bookmark_cleanup

source("R/helpers_bookmarks.R", local = TRUE)

bookmark_cleanup(pool)
