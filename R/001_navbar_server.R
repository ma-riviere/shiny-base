# Navbar server module
# Handles language switching, user profile display, profile modal, and profile updates

navbar_server <- function(
    id
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns
        # Reactive for user nickname (used in navbar and updated after profile save)
        user_nickname <- reactiveVal(NULL)

        # ------ UI ----------------------------------------------------------------

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
            ignoreInit = TRUE
        )

        # ------ OUTPUT --------------------------------------------------------

        output$user_nickname <- renderText({
            auth_info <- session$userData$auth0_info

            # Use reactive value if available (after profile update)
            if (!purrr::is_empty(user_nickname())) {
                return(user_nickname())
            }

            # Otherwise read from auth0_info (initial load)
            if (!purrr::is_empty(auth_info)) {
                purrr::pluck(auth_info, "nickname") %||%
                    purrr::pluck(auth_info, "name") %||%
                    purrr::pluck(auth_info, "email") %||%
                    "User"
            } else {
                "No Auth0"
            }
        })

        # ------ PROFILE MODAL -------------------------------------------------

        # Open profile modal
        observeEvent(input$open_profile, {
            req(session$userData$auth0_info)
            cat("Open profile modal\n", file = stderr())
            ns <- session$ns
            auth_info <- session$userData$auth0_info

            current_nickname <- purrr::pluck(auth_info, "nickname") %||% ""
            picture_url <- purrr::pluck(auth_info, "picture")
            email <- purrr::pluck(auth_info, "email") %||% ""

            showModal(modalDialog(
                title = tr("Profile"),
                easyClose = TRUE,
                footer = tagList(
                    actionButton(
                        ns("save_profile"),
                        tr("Save"),
                        class = "btn-primary i18n",
                        `data-key` = "Save"
                    ),
                    modalButton(tr("Cancel"))
                ),
                div(
                    class = "profile-modal-content",
                    if (!purrr::is_empty(picture_url)) {
                        div(
                            class = "profile-picture-section",
                            tags$img(
                                src = picture_url,
                                class = "profile-picture",
                                alt = "Profile picture"
                            )
                        )
                    },
                    div(
                        class = "profile-info-section",
                        div(
                            class = "mb-3",
                            tags$label(class = "form-label i18n", `data-key` = "Email", tr("Email")),
                            tags$div(class = "form-control-plaintext", email)
                        ),
                        div(
                            class = "mb-3",
                            textInput(
                                ns("profile_nickname"),
                                label = tagList(
                                    tags$span(class = "i18n", `data-key` = "Nickname", tr("Nickname"))
                                ),
                                value = current_nickname
                            )
                        ),
                        div(
                            class = "mb-3",
                            selectInput(
                                ns("profile_language"),
                                label = tagList(
                                    tags$span(
                                        class = "i18n",
                                        `data-key` = "Preferred Language",
                                        tr("Preferred Language")
                                    )
                                ),
                                choices = get_language_choices(),
                                selected = purrr::pluck(auth_info, "user_metadata", "language") %||%
                                    i18n$get_key_translation()
                            )
                        )
                    )
                )
            ))
        })

        # Save profile changes
        observeEvent(input$save_profile, {
            auth_info <- session$userData$auth0_info
            new_nickname <- input$profile_nickname
            new_language <- input$profile_language

            if (!purrr::is_empty(auth_info) && !purrr::is_empty(new_nickname)) {
                user_id <- purrr::pluck(auth_info, "sub")

                tryCatch(
                    {
                        auth0_api <- Auth0API$new()

                        # Update nickname
                        auth0_api$update_user_nickname(user_id, new_nickname)

                        # Update language preference in user_metadata
                        if (!purrr::is_empty(new_language)) {
                            current_metadata <- purrr::pluck(auth_info, "user_metadata") %||% list()
                            current_metadata$language <- new_language
                            auth0_api$update_user_metadata(user_id, current_metadata)

                            # Update local session data
                            session$userData$auth0_info$user_metadata <- current_metadata

                            # Apply language change immediately
                            shiny.i18n::update_lang(new_language)
                            updateSelectInput(session, "language", selected = new_language)
                        }

                        # Update local session data for nickname
                        session$userData$auth0_info$nickname <- new_nickname

                        # Update reactive value to trigger UI update
                        user_nickname(new_nickname)

                        # Close modal
                        removeModal()

                        # Show success notification
                        shinyWidgets::show_toast(
                            title = tr("Profile updated successfully"),
                            type = "success",
                            timer = 3000,
                            position = "bottom-end"
                        )
                    },
                    error = \(e) {
                        shinyWidgets::show_toast(
                            title = paste(tr("Error updating profile:"), e$message),
                            type = "error",
                            timer = 5000,
                            position = "bottom-end"
                        )
                    }
                )
            }
        })
    })
}
