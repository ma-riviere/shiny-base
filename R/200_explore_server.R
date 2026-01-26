explore_server <- function(
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

        has_data <- reactive(
            !purrr::is_empty(values$data),
            label = "dataset_has_data"
        )

        # ------ REACTIVE ------------------------------------------------------

        # Load dataset when selection changes or refresh_datasets is triggered
        observeEvent(
            list(watch("refresh_datasets"), selected_dataset_id()),
            label = "dataset_load",
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

        # Initialize summary row module ONCE when first dataset is loaded
        # (row_id is reactive so module updates when user switches datasets)
        observeEvent(
            values$dataset,
            label = "dataset_init_summary_row",
            {
                dataset_row_server(
                    "summary_row",
                    all_datasets = reactive(values$dataset),
                    row_id = reactive(values$dataset$id),
                    on_click = NULL,
                    nav_select_callback = nav_select_callback
                )
                # RBAC: hide delete button if user has no permission (hidden by default in UI)
                if (!can("delete:dataset")) shinyjs::hide("summary_row-delete")
            },
            once = TRUE
        )

        # Upload modal trigger
        observeEvent(
            input$open_upload,
            trigger("show_upload_modal"),
            label = "dataset_open_upload"
        )

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

        # Show/hide empty state based on data presence
        observe(
            shinyjs::toggle("empty_state", condition = !has_data()),
            label = "dataset_empty_toggle"
        )

        # Navigate to home page
        observeEvent(input$go_home, label = "dataset_go_home", {
            if (!is.null(nav_select_callback)) {
                nav_select_callback("home")
            }
        })
    })
}
