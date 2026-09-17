# Navbar server module
# Handles language switching and user profile display; hosts the profile modal (child module)

navbar_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # ------ UI ------------------------------------------------------------

        # Disable user menu items when auth0 is bypassed
        if (auth0r::auth0_disabled()) {
            shinyjs::addClass("open_profile", "disabled")
            shinyjs::addClass("logout_wrapper", "disabled")
        }

        # ------ I18N ----------------------------------------------------------

        # Live language switching via JavaScript
        # Note: initial language resolution is handled in server.R
        # Here we only react to explicit user selection (ignoreInit = TRUE)
        observeEvent(
            input$language,
            {
                shiny.i18n::update_lang(input$language)
                # Store in cookie only on explicit selection
                set_language_cookie(input$language, session)
            },
            ignoreInit = TRUE,
            label = "navbar_language_switch"
        )

        # ------ MODULE --------------------------------------------------------

        # The profile modal is only opened from here, so it is our child module (inputs are
        # navbar-profile-*), not a sibling relayed by server.R like the rename modal. It returns
        # open() and `updated`, a counter bumped after each successful save: the modal writes the
        # new nickname/language into session$userData$auth0_info first, we re-read it from there.
        profile_modal_module <- profile_modal_server("profile")

        # ------ PROFILE -------------------------------------------------------

        observeEvent(input$open_profile, profile_modal_module$open(), label = "navbar_open_profile")

        # Sync language selector when profile is updated
        observeEvent(
            profile_modal_module$updated(),
            {
                new_lang <- purrr::pluck(session$userData$auth0_info, "user_metadata", "language")
                if (!purrr::is_empty(new_lang)) {
                    updateSelectInput(session, "language", selected = new_lang)
                }
            },
            ignoreInit = TRUE,
            label = "navbar_sync_profile_lang"
        )

        # ------ OUTPUT --------------------------------------------------------

        output$user_nickname <- renderText({
            profile_modal_module$updated() # Re-render when profile changes

            auth_info <- session$userData$auth0_info
            if (!purrr::is_empty(auth_info)) {
                purrr::pluck(auth_info, "nickname") %||%
                    purrr::pluck(auth_info, "name") %||%
                    purrr::pluck(auth_info, "email") %||%
                    "User"
            } else {
                # Use guest user's auth0_sub (e.g., "guest_6142f68686ff") if available
                purrr::pluck(session$userData$user, "auth0_sub") %||% "Guest"
            }
        })
    })
}
