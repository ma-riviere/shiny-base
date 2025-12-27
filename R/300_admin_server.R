# Admin dashboard server module
# Placeholder for future admin functionality (user management, system monitoring, etc.)
# Access gated by is_admin() check - stops all logic if user is not an admin.
#
# NOTE: Usage analytics moved to Matomo (see MATOMO.md).
# Shiny OTEL handles performance tracing. This module can be expanded for:
# - User management (list users, change roles)
# - System health (DB connection status, error logs)
# - App configuration
admin_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        # SECURITY GATE: Stop immediately if not admin
        req(is_admin())

        ns <- session$ns

        # ------ OUTPUT --------------------------------------------------------

        output$placeholder_text <- renderText({
            "Admin dashboard placeholder. Add user management or system monitoring here."
        })
    })
}
