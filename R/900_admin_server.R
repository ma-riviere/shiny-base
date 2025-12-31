# Admin dashboard server module
# Provides user session monitoring and system administration.
# Access gated by can("view:admin") - stops all logic if user lacks permission.
#
# NOTE: Usage analytics moved to Matomo (see MATOMO.md)
# Shiny OTEL handles performance tracing.
#
# @param active_page Reactive returning the current main nav page (e.g., "home", "admin")
# @param r Shared reactiveValues for cross-module state

admin_server <- function(id, active_page, r) {
    moduleServer(id, function(input, output, session) {
        # SECURITY GATE: Exit early if no admin permission.
        if (!can("view:admin")) {
            return()
        }

        # Hide tabs based on permissions
        if (!can("view:admin:auth0")) {
            bslib::nav_hide("admin_tabs", target = "users")
        }

        initialized <- reactiveVal(FALSE)

        # Helper: check if user is on admin page AND specific sub-tab
        is_on_tab <- function(tab_value) {
            reactive(isTRUE(active_page() == "admin") && isTRUE(input$admin_tabs == tab_value))
        }

        # ------ INIT ----------------------------------------------------------
        # Delay sub-module instantiation until user first visits admin page
        observe(label = "admin_init", {
            req(!initialized())
            req(active_page() == "admin")
            req(can("view:admin"))
            log_info("[ADMIN] Initializing admin server")

            # ------ SUB-MODULES -----------------------------------------------
            system_server("system", is_active = is_on_tab("system"))
            auth0_server("auth0", is_active = is_on_tab("users"), r = r)
            otel_server("otel", is_active = is_on_tab("otel"))

            initialized(TRUE)
        }) |>
            bindEvent(active_page(), ignoreInit = TRUE)
    })
}
