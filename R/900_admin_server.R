# Admin dashboard server module
# Provides user session monitoring and system administration.
# Access gated by has_permission("view:admin") - stops all logic if user lacks permission.
#
# NOTE: Usage analytics moved to Matomo (see MATOMO.md)
# Shiny OTEL handles performance tracing.
#
# @param active_page Reactive returning the current main nav page (e.g., "home", "admin")

admin_server <- function(id, active_page) {
    moduleServer(id, function(input, output, session) {
        # SECURITY GATE: Exit early if no admin permission.
        # Use has_permission() (returns bool) not req_permission() (throws silent error).
        if (!has_permission("view:admin")) {
            return()
        }

        # Helper: check if user is on admin page AND specific sub-tab
        is_on_tab <- function(tab_value) {
            reactive(isTRUE(active_page() == "admin") && isTRUE(input$admin_tabs == tab_value))
        }

        # ------ SUB-MODULES ------------------------------------------------------
        auth0_server("auth0", is_active = is_on_tab("users"))
        otel_server("otel", is_active = is_on_tab("otel"))
        system_server("system", is_active = is_on_tab("system"))
    })
}
