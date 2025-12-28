# Admin dashboard server module
# Provides user session monitoring and system administration.
# Access gated by is_admin() check - stops all logic if user is not an admin.
#
# NOTE: Usage analytics moved to Matomo (see MATOMO.md).
# Shiny OTEL handles performance tracing.

admin_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        # SECURITY GATE: Stop immediately if not admin
        req(is_admin())

        ns <- session$ns

        # ------ SUB-MODULES ----------------------------------------------------
        auth0_server("auth0", is_active = reactive(input$admin_tabs == "users"))
        system_server("system", is_active = reactive(input$admin_tabs == "system"))
    })
}
