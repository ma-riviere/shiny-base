# OTel Trace Viewer UI (app-specific)
# Uses reusable utilities from R/shiny-utils/otel.R
# CSS: www/sass/_otel.scss
#
# NOTE: This viewer is disabled in production (ENV=prod). Production deployments
# should use external tracing backends (Jaeger, Grafana, etc.) instead.

otel_ui <- function(id) {
    ns <- NS(id)

    # In production, show disabled state instead of trace viewer
    if (isTRUE(is_prod)) {
        return(tagList(
            div(
                class = "py-3",
                div(
                    class = "alert alert-secondary",
                    tags$h5(class = "alert-heading", tr("Trace viewer disabled in production")),
                    p(tr("The in-app trace viewer is only available in development mode.")),
                    p(
                        tr("For production tracing, use an external OTLP backend:"),
                        tags$ul(
                            class = "mb-0 mt-2",
                            tags$li(tags$a(href = "https://www.jaegertracing.io/", target = "_blank", "Jaeger")),
                            tags$li(tags$a(
                                href = "https://grafana.com/oss/tempo/",
                                target = "_blank",
                                "Grafana Tempo"
                            )),
                            tags$li(tags$a(href = "https://logfire.pydantic.dev/", target = "_blank", "Logfire"))
                        )
                    ),
                    tags$hr(),
                    p(
                        class = "mb-0 small text-muted",
                        tr("Configure via OTEL_EXPORTER_OTLP_ENDPOINT in .Renviron")
                    )
                )
            )
        ))
    }

    tagList(
        div(
            class = "py-3",
            div(
                class = "d-flex justify-content-between align-items-center mb-3",
                h4(class = "i18n mb-0", `data-key` = "Traces", tr("Traces")),
                div(
                    class = "d-flex gap-2 align-items-center",
                    span(
                        class = "text-muted small",
                        textOutput(ns("span_count"), inline = TRUE)
                    ),
                    tagAppendAttributes(
                        selectInput(
                            ns("time_filter"),
                            label = NULL,
                            choices = c(
                                "Last 5 min" = "5",
                                "Last 15 min" = "15",
                                "Last 1 hour" = "60",
                                "All" = "0"
                            ),
                            selected = "5",
                            width = "120px"
                        ),
                        class = "mb-0"
                    ),
                    bslib::input_task_button(
                        ns("refresh"),
                        label = "Update",
                        icon = tags$i(class = "bi bi-arrow-clockwise"),
                        label_busy = "Updating...",
                        type = "outline-secondary",
                        class = "btn-sm"
                    ),
                    actionButton(
                        ns("clear"),
                        label = tagList(tags$i(class = "bi bi-trash"), "Clear"),
                        class = "btn-sm btn-outline-danger",
                        title = tr("Clear traces")
                    )
                )
            ),

            # Static container - rows inserted/removed via JS
            div(
                class = "otel-container",
                div(
                    class = "otel-header",
                    div(class = "otel-col otel-col-time", "Time"),
                    div(class = "otel-col otel-col-session", "User"),
                    div(class = "otel-col otel-col-span", "Span"),
                    div(class = "otel-col otel-col-origin", "Origin"),
                    div(class = "otel-col otel-col-duration", "Duration"),
                    div(class = "otel-col otel-col-timeline", "Timeline")
                ),
                div(
                    id = ns("rows_container"),
                    class = "otel-rows"
                )
            ),

            # Empty state (shown/hidden via JS)
            div(
                id = ns("empty_state"),
                class = "otel-empty",
                style = "display: none;",
                tags$i(class = "bi bi-activity"),
                p(tr("No traces captured yet")),
                p(class = "small", tr("Interact with the app to generate traces"))
            ),

            # Not configured state
            uiOutput(ns("not_configured"))
        )
    )
}
