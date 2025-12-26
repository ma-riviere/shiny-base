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
        # ----- DATASET SUMMARY ------------------------------------------------
        div(
            class = "mb-4",
            dataset_row_ui(ns("summary_row"), clickable = FALSE)
        ),

        # ----- DATA PREVIEW ---------------------------------------------------
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
