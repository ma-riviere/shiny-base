# Profile modal UI
# Contains the modal dialog for viewing/editing user profile

profile_modal_ui <- function(ns, auth_info) {
    current_nickname <- purrr::pluck(auth_info, "nickname") %||% ""
    picture_url <- purrr::pluck(auth_info, "picture")
    email <- purrr::pluck(auth_info, "email") %||% ""
    current_language <- purrr::pluck(auth_info, "user_metadata", "language") %||%
        i18n$get_key_translation()

    # Extract roles from custom claim
    roles_claim <- getOption("auth0_roles_claim", "https://shiny-base.ma-riviere.com/roles")
    roles <- purrr::pluck(auth_info, roles_claim) %||% character(0)
    roles_text <- if (purrr::is_empty(roles)) {
        tr("None")
    } else {
        paste(roles, collapse = ", ")
    }

    modalDialog(
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
                    tags$label(class = "form-label i18n", `data-key` = "Roles", tr("Roles")),
                    tags$div(class = "form-control-plaintext", roles_text)
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
                        selected = current_language
                    )
                )
            )
        )
    )
}
