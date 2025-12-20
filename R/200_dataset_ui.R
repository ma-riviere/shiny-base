dataset_ui <- function(id) {
    ns <- NS(id)
    div(
        id = ns("main"),
        class = "page page-dataset",
        div(
            class = "page-header",
            h1(class = "i18n", `data-key` = "Dataset Explorer", tr("Dataset Explorer")),
            p(
                class = "lead",
                uiOutput(ns("dataset_description"), inline = TRUE)
            )
        ),
        # Dataset info cards
        div(
            class = "content-grid",
            div(
                class = "card stat-card",
                div(class = "stat-icon", bsicons::bs_icon("file-earmark-text")),
                div(
                    class = "stat-content",
                    span(class = "stat-value", textOutput(ns("dataset_name"), inline = TRUE)),
                    span(
                        class = "stat-label i18n",
                        `data-key` = "Dataset",
                        tr("Dataset")
                    )
                )
            ),
            div(
                class = "card stat-card",
                div(class = "stat-icon", bsicons::bs_icon("table")),
                div(
                    class = "stat-content",
                    span(class = "stat-value", textOutput(ns("row_count"), inline = TRUE)),
                    span(class = "stat-label i18n", `data-key` = "Rows", tr("Rows"))
                )
            ),
            div(
                class = "card stat-card",
                div(class = "stat-icon", bsicons::bs_icon("columns")),
                div(
                    class = "stat-content",
                    span(class = "stat-value", textOutput(ns("col_count"), inline = TRUE)),
                    span(class = "stat-label i18n", `data-key` = "Columns", tr("Columns"))
                )
            )
        ),
        # Data actions (download, etc.)
        div(
            class = "content-actions mb-3",
            downloadButton(
                ns("download_csv"),
                label = tags$span(class = "i18n", `data-key` = "Download", tr("Download")),
                class = "btn-outline-primary"
            )
        ),
        # Data preview and summary
        div(
            class = "content-section",
            div(
                class = "card",
                h3(class = "i18n", `data-key` = "Data Preview", tr("Data Preview")),
                div(
                    class = "table-container",
                    DT::dataTableOutput(ns("data_preview"))
                )
            )
        ),
        # Empty state when no dataset selected
        uiOutput(ns("empty_state"))
    )
}
