explore_ui <- function(id) {
    ns <- NS(id)
    div(
        id = ns("main"),
        class = "page page-dataset",
        div(
            class = "page-header",
            h1(class = "i18n", `data-key` = "Explore", tr("Explore")),
            p(
                class = "lead",
                uiOutput(ns("dataset_description"), inline = TRUE)
            )
        ),
        # ----- DATASET SUMMARY ------------------------------------------------
        div(
            class = "mb-4",
            dataset_row_ui(ns("summary_row"), clickable = FALSE, can_delete = TRUE) # Hiding it server-side if needed
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
        # ----- EMPTY STATE ----------------------------------------------------
        shinyjs::hidden(
            div(
                id = ns("empty_state"),
                class = "empty-state-overlay",
                div(
                    class = "empty-state",
                    bsicons::bs_icon("table", size = "3rem"),
                    p(
                        class = "i18n",
                        `data-key` = "No dataset selected",
                        tr("No dataset selected")
                    ),
                    p(
                        tags$small(
                            class = "text-muted i18n",
                            `data-key` = "Upload a new dataset or go to Home to select one",
                            tr("Upload a new dataset or go to Home to select one")
                        )
                    ),
                    div(
                        class = "empty-state-actions",
                        actionButton(
                            ns("open_upload"),
                            tagList(
                                bsicons::bs_icon("upload"),
                                tags$span(class = "i18n", `data-key` = "Upload Dataset", tr("Upload Dataset"))
                            ),
                            class = "btn-primary"
                        ),
                        actionButton(
                            ns("go_home"),
                            tagList(
                                bsicons::bs_icon("house"),
                                tags$span(class = "i18n", `data-key` = "Go to Home", tr("Go to Home"))
                            ),
                            class = "btn-outline-secondary"
                        )
                    )
                )
            )
        )
    )
}
