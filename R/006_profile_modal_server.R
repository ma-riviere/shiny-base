# Profile modal server module
# Displays and saves the current user's profile (nickname, language).
# Child of the navbar, the only place that opens it. Returns open() and the `updated` counter.

profile_modal_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Bumped after each successful save. A counter, not the profile itself: the data lives in
        # session$userData$auth0_info (written before the bump), the parent re-reads it from there.
        updated <- reactiveVal(0L)

        # ------ MODAL DISPLAY -------------------------------------------------

        open <- function() {
            if (purrr::is_empty(session$userData$auth0_info)) {
                return()
            }
            showModal(profile_modal_ui(ns, session$userData$auth0_info))
        }

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

                    # Notify the parent (navbar) to re-read auth0_info
                    updated(updated() + 1L)

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

        return(list(open = open, updated = reactive(updated())))
    })
}
