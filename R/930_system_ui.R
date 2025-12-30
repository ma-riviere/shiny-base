# System admin sub-tab UI
# Shows log viewer and system health information

system_ui <- function(id) {
    ns <- NS(id)
    div(
        class = "py-3",
        # Log Viewer
        h4(
            class = "i18n mb-3",
            `data-key` = "Log Viewer",
            tr("Log Viewer")
        ),
        div(
            class = "d-flex justify-content-between align-items-center mb-2",
            div(
                class = "text-muted small",
                textOutput(ns("log_file_name"), inline = TRUE)
            ),
            div(
                class = "d-flex gap-2",
                actionButton(
                    ns("scroll_to_bottom"),
                    label = tagList(tags$i(class = "bi bi-arrow-down-circle me-1"), tr("Scroll to end")),
                    class = "btn-sm btn-outline-secondary"
                ),
                actionButton(
                    ns("refresh_logs"),
                    label = tagList(tags$i(class = "bi bi-arrow-clockwise me-1"), tr("Refresh")),
                    class = "btn-sm btn-outline-secondary"
                )
            )
        ),
        div(
            id = ns("log_container"),
            class = "log-viewer-container",
            style = paste0(
                "background-color: #1e1e1e;",
                "color: #d4d4d4;",
                "font-family: 'Consolas', 'Monaco', 'Courier New', monospace;",
                "font-size: 0.8rem;",
                "padding: 1rem;",
                "border-radius: 0.375rem;",
                "height: 500px;",
                "overflow-y: auto;",
                "white-space: pre-wrap;",
                "word-break: break-all;"
            ),
            verbatimTextOutput(ns("log_content"), placeholder = TRUE)
        )
    )
}
