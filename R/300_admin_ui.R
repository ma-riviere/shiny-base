admin_ui <- function(id) {
    ns <- NS(id)
    div(
        id = ns("main"),
        class = "page page-admin",
        div(
            class = "page-header",
            h1(class = "i18n", `data-key` = "Admin Dashboard", tr("Admin Dashboard")),
            p(
                class = "lead i18n",
                `data-key` = "System administration and monitoring.",
                tr("System administration and monitoring.")
            )
        ),
        # ------ PLACEHOLDER ---------------------------------------------------
        div(
            class = "content-section",
            div(
                class = "card",
                div(
                    class = "card-body",
                    p(
                        class = "text-muted",
                        textOutput(ns("placeholder_text"))
                    ),
                    tags$ul(
                        tags$li(
                            strong("Usage analytics:"),
                            " See MATOMO.md for Matomo integration (visitor tracking, devices, retention)"
                        ),
                        tags$li(
                            strong("Performance tracing:"),
                            " Use Shiny's native OpenTelemetry (reactive execution, timing, cross-process tracing)"
                        ),
                        tags$li(
                            strong("Future features:"),
                            " User management, system health monitoring, app configuration"
                        )
                    )
                )
            )
        )
    )
}
