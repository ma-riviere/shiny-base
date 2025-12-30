# Auth0 / Users admin sub-tab UI
# Shows currently connected users and recently connected users

auth0_ui <- function(id) {
    ns <- NS(id)
    div(
        class = "py-3",
        # Currently connected users
        h4(
            class = "i18n mb-3",
            `data-key` = "Currently Connected",
            tr("Currently Connected")
        ),
        active_sessions_ui(ns("active_sessions")),
        hr(class = "my-4"),
        # Recently connected users table
        h4(
            class = "i18n mb-3",
            `data-key` = "Recently Connected",
            tr("Recently Connected")
        ),
        div(
            class = "table-responsive",
            tableOutput(ns("recent_users_table"))
        )
    )
}
