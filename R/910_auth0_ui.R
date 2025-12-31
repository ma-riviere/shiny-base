# Auth0 / Users admin sub-tab UI
# Shows currently connected users OR all users, plus role management

auth0_ui <- function(id) {
    ns <- NS(id)
    div(
        class = "py-3",
        # Currently connected users (default view)
        shinyjs::hidden(
            div(
                id = ns("section_connected"),
                h4(
                    class = "i18n mb-3",
                    `data-key` = "Currently Connected",
                    tr("Currently Connected")
                ),
                active_sessions_ui(ns("active_sessions"))
            )
        ),
        # All users view
        shinyjs::hidden(
            div(
                id = ns("section_all"),
                h4(
                    class = "i18n mb-3",
                    `data-key` = "All Users",
                    tr("All Users")
                ),
                uiOutput(ns("all_users_cards"))
            )
        ),
        # Roles management section (always visible)
        hr(class = "my-4"),
        h4(
            class = "i18n mb-3",
            `data-key` = "Role Management",
            tr("Role Management")
        ),
        roles_section_ui(ns("roles"))
    )
}
