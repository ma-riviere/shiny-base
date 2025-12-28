# Profile UI components
# Profile modal for current user (editable)
# Uses extract_profile_info() from shiny-utils/auth0.R

# Profile modal UI (editable, for current user)
profile_modal_ui <- function(ns, auth_info) {
    info <- extract_profile_info(auth_info)

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
            if (!purrr::is_empty(info$picture_url)) {
                div(
                    class = "profile-picture-section",
                    tags$img(
                        src = info$picture_url,
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
                    tags$div(class = "form-control-plaintext", info$email)
                ),
                div(
                    class = "mb-3",
                    tags$label(class = "form-label i18n", `data-key` = "Roles", tr("Roles")),
                    tags$div(class = "form-control-plaintext", info$roles_text)
                ),
                div(
                    class = "mb-3",
                    textInput(
                        ns("profile_nickname"),
                        label = tagList(
                            tags$span(class = "i18n", `data-key` = "Nickname", tr("Nickname"))
                        ),
                        value = info$nickname
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
                        selected = info$language
                    )
                )
            )
        )
    )
}
