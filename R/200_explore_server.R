explore_server <- function(
    id,
    selected_dataset_id = reactive(NULL),
    nav_select_callback = NULL,
    on_edit
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

                # Fetch dataset from DB (user-scoped: never trust a client-supplied id)
                dataset_row <- db_get_dataset(dataset_id, purrr::pluck(session$userData$user, "id"))
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
                        show_toast(
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

        # Summary-row action handlers (edit / download / delete), shared
        # "one observer for all rows" module (single row here)
        dataset_actions_server(
            "actions",
            datasets = reactive(values$dataset),
            on_edit = on_edit,
            nav_select_callback = nav_select_callback
        )

        # Upload modal trigger
        observeEvent(
            input$open_upload,
            trigger("show_upload_modal"),
            label = "dataset_open_upload"
        )

        # ------ OUTPUT --------------------------------------------------------

        output$dataset_summary <- renderUI({
            req(values$dataset)
            dataset_row_ui(
                NS(ns("actions")),
                values$dataset,
                can_delete = can("delete:dataset")
            )
        })

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
