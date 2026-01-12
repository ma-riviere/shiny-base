# Navbar server module
# Handles language switching and user profile display

navbar_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # ------ UI ------------------------------------------------------------

        # Disable user menu items when auth0 is bypassed
        if (isTRUE(getOption("auth0_disable"))) {
            shinyjs::addClass("profile_link", "disabled")
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

        # ------ PROFILE -------------------------------------------------------

        # Open profile modal via trigger
        observeEvent(
            input$open_profile,
            {
                trigger("show_profile_modal")
            },
            label = "navbar_open_profile"
        )

        # Sync language selector when profile is updated
        on(
            "profile_updated",
            {
                new_lang <- purrr::pluck(session$userData$auth0_info, "user_metadata", "language")
                if (!purrr::is_empty(new_lang)) {
                    updateSelectInput(session, "language", selected = new_lang)
                }
            },
            label = "navbar_sync_profile_lang"
        )

        # ------ OUTPUT --------------------------------------------------------

        output$user_nickname <- renderText({
            watch("profile_updated") # Re-render when profile changes

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
