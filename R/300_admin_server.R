# Admin dashboard server module
# Provides user session monitoring and system administration.
# Access gated by is_admin() check - stops all logic if user is not an admin.
#
# NOTE: Usage analytics moved to Matomo (see MATOMO.md)
# Shiny OTEL handles performance tracing.
#
# @param active_page Reactive returning the current main nav page (e.g., "home", "admin")

admin_server <- function(id, active_page) {
    moduleServer(id, function(input, output, session) {
        # SECURITY GATE: Stop immediately if not admin
        req(is_admin())

        ns <- session$ns

        # Helper: check if user is on admin page AND specific sub-tab
        is_on_tab <- function(tab_value) {
            reactive(isTRUE(active_page() == "admin") && isTRUE(input$admin_tabs == tab_value))
        }

        # ------ SUB-MODULES ----------------------------------------------------
        auth0_server("auth0", is_active = is_on_tab("users"))
        otel_server("otel", is_active = is_on_tab("otel"))
        system_server("system", is_active = is_on_tab("system"))
    })
}
