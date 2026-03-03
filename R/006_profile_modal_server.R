# Profile modal server module
# Handles displaying and saving user profile changes

profile_modal_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # ------ MODAL DISPLAY -------------------------------------------------

        on("show_profile_modal", label = "profile_show_modal", {
            req(session$userData$auth0_info)
            showModal(profile_modal_ui(ns, session$userData$auth0_info))
        })

        # ------ SAVE PROFILE --------------------------------------------------

        observeEvent(input$save_profile, label = "profile_save", {
            auth_info <- session$userData$auth0_info
            new_nickname <- input$profile_nickname
            new_language <- input$profile_language

            if (purrr::is_empty(auth_info) || purrr::is_empty(new_nickname)) {
                return()
            }

            user_id <- purrr::pluck(auth_info, "sub")

            tryCatch(
                {
                    # Update nickname
                    auth0_mgmt$update_user(user_id, nickname = new_nickname)

                    # Update language preference in user_metadata
                    if (!purrr::is_empty(new_language)) {
                        current_metadata <- purrr::pluck(auth_info, "user_metadata") %||% list()
                        current_metadata$language <- new_language
                        auth0_mgmt$update_user_metadata(user_id, current_metadata)

                        # Update local session data
                        session$userData$auth0_info$user_metadata <- current_metadata

                        # Apply language change immediately
                        shiny.i18n::update_lang(new_language)
                    }

                    # Update local session data for nickname
                    session$userData$auth0_info$nickname <- new_nickname

                    # Notify navbar to update display
                    trigger("profile_updated")

                    removeModal()

                    show_toast(
                        title = tr("Profile updated successfully"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    show_toast(
                        title = paste(tr("Error updating profile:"), e$message),
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })
    })
}
