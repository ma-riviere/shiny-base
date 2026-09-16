# Language choices for the navbar and profile modal. shinyutils initializes the translator.

# Get available languages with display names and flag emoji
get_language_choices <- function() {
    purrr::set_names(
        i18n$get_languages(),
        c("\U0001F1EC\U0001F1E7 EN", "\U0001F1EB\U0001F1F7 FR")
    )
}
