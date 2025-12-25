dataset_server <- function(
    id,
    selected_dataset_id = reactive(NULL),
    nav_select_callback = NULL
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(
            dataset = NULL,
            data = NULL
        )

        # Track if summary row module is initialized
        row_initialized <- reactiveVal(FALSE)

        # ------ REACTIVE ------------------------------------------------------

        # Load dataset when selection changes or refresh_datasets is triggered
        observeEvent(
            list(watch("refresh_datasets"), selected_dataset_id()),
            {
                dataset_id <- selected_dataset_id()

                if (purrr::is_empty(dataset_id)) {
                    values$dataset <- NULL
                    values$data <- NULL
                    return()
                }

                # Fetch dataset from DB
                dataset_row <- db_get_dataset(dataset_id)
                if (purrr::is_empty(dataset_row)) {
                    values$dataset <- NULL
                    values$data <- NULL
                    return()
                }

                # Parse JSON data to data frame
                tryCatch(
                    {
                        values$data <- db_parse_dataset_data(dataset_row$data)
                        # Add row_count and col_count (db_get_dataset doesn't compute these)
                        dataset_row$row_count <- nrow(values$data)
                        dataset_row$col_count <- ncol(values$data)
                    },
                    error = \(e) {
                        values$data <- NULL
                        dataset_row$row_count <- 0L
                        dataset_row$col_count <- 0L
                        shinyWidgets::show_toast(
                            title = paste(tr("Error parsing dataset:"), e$message),
                            type = "error",
                            timer = 5000,
                            position = "bottom-end"
                        )
                    }
                )

                values$dataset <- dataset_row
            }
        )

        has_data <- reactive({
            !purrr::is_empty(values$data)
        })

        # Initialize summary row module ONCE (but row_id is reactive for switching)
        observe({
            req(values$dataset)
            req(!row_initialized())

            dataset_row_server(
                "summary_row",
                all_datasets = reactive({
                    if (purrr::is_empty(values$dataset)) {
                        return(data.frame())
                    }
                    values$dataset
                }),
                # Pass as reactive so it updates when user switches datasets
                row_id = reactive(values$dataset$id),
                on_click = NULL,
                nav_select_callback = nav_select_callback
            )
            row_initialized(TRUE)
        })

        # Open upload modal
        observeEvent(input$open_upload, {
            trigger("show_upload_modal")
        })

        # ------ OUTPUT --------------------------------------------------------

        output$dataset_description <- renderUI({
            if (!has_data()) {
                return(
                    tags$span(
                        class = "i18n",
                        `data-key` = "Select a dataset to explore",
                        tr("Select a dataset to explore")
                    )
                )
            }
            tags$span(
                class = "i18n",
                `data-key` = "Explore your uploaded dataset",
                tr("Explore your uploaded dataset")
            )
        })

        output$data_preview <- DT::renderDataTable({
            req(has_data())
            DT::datatable(
                values$data,
                options = list(
                    pageLength = 10,
                    scrollX = TRUE,
                    dom = "frtip"
                ),
                class = "display compact",
                rownames = FALSE
            )
        })

        output$empty_state <- renderUI({
            if (has_data()) {
                return(NULL)
            }
            div(
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
        })

        # Navigate to home page
        observeEvent(input$go_home, {
            if (!is.null(nav_select_callback)) {
                nav_select_callback("home")
            }
        })
    })
}
