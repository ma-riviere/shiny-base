# Translation helper using shiny.i18n
# Provides a global Translator instance and helper functions for translations

# Initialize translator from JSON file
i18n <- shiny.i18n::Translator$new(translation_json_path = "data/translations.json")
i18n$set_translation_language("en")

# Shorthand for translation in UI
# Usage: tr("Home") or tr("Settings")
tr <- function(text) {
    i18n$t(text)
}

# Get available languages with display names and flag emoji
get_language_choices <- function() {
    purrr::set_names(
        i18n$get_languages(),
        c("\U0001F1EC\U0001F1E7 EN", "\U0001F1EB\U0001F1F7 FR")
    )
}

# ------ LANGUAGE RESOLUTION ---------------------------------------------------
# Config constants (LANGUAGE_COOKIE_NAME, etc.) are defined in global.R

# Resolve language preference using the following hierarchy:
# 1. Auth0 user_metadata (source of truth if logged in)
# 2. Cookie (remembers choice from previous session)
# 3. Browser language preference (fallback)
# 4. App default
#
# @param auth_info Auth0 user info from session$userData$auth0_info (can be NULL)
# @param session Shiny session object (for cookie and browser language access)
# @return Character string with the resolved language code
resolve_language <- function(auth_info = NULL, session) {
    # 1. Auth0 user_metadata (highest priority)
    auth_lang <- purrr::pluck(auth_info, "user_metadata", "language")
    if (!purrr::is_empty(auth_lang) && auth_lang %in% i18n$get_languages()) {
        return(auth_lang)
    }

    # 2. Cookie
    cookie_lang <- cookies::get_cookie(LANGUAGE_COOKIE_NAME, session = session)
    if (!purrr::is_empty(cookie_lang) && cookie_lang %in% i18n$get_languages()) {
        return(cookie_lang)
    }

    # 3. Browser language preference
    browser_lang <- extract_browser_language(session)
    if (!purrr::is_empty(browser_lang) && browser_lang %in% i18n$get_languages()) {
        return(browser_lang)
    }

    # 4. Default
    return(DEFAULT_LANGUAGE)
}

# Extract the primary language code from browser's Accept-Language header
# Example: "en-US,en;q=0.9,fr;q=0.8" -> "en"
#
# @param session Shiny session object
# @return Two-letter language code or NULL if not available
extract_browser_language <- function(session) {
    accept_lang <- session$request$HTTP_ACCEPT_LANGUAGE
    if (purrr::is_empty(accept_lang)) {
        return(NULL)
    }
    # Extract first two characters (primary language code)
    substr(accept_lang, 1, 2)
}

# Set the language cookie (only call on explicit user selection)
#
# @param language The language code to store
# @param session Shiny session object
set_language_cookie <- function(language, session) {
    cookies::set_cookie(
        cookie_name = LANGUAGE_COOKIE_NAME,
        cookie_value = language,
        expiration = LANGUAGE_COOKIE_EXPIRATION,
        session = session
    )
}

# Apply a language to the app (updates i18n and UI)
#
# @param language The language code to apply
# @param session Shiny session object
# @param navbar_language_input_id The namespaced ID of the navbar language selector
apply_language <- function(language, session, navbar_language_input_id = "navbar-language") {
    shiny.i18n::update_lang(language)
    updateSelectInput(session, navbar_language_input_id, selected = language)
}
