home_server <- function(id, row_count_filter = reactive(c(0, 100000)), nav_select_callback = NULL) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(datasets = NULL)

        # ------ REACTIVE ------------------------------------------------------

        # Fetch datasets when user is loaded or refresh is triggered
        observe({
            watch("refresh_datasets")
            user_id <- purrr::pluck(session$userData$user, "id")
            req(user_id)
            values$datasets <- db_get_user_datasets(pool, user_id)
        })

        # Filter datasets based on row count slider from sidebar
        filtered_datasets <- reactive({
            req(values$datasets)
            filter_range <- row_count_filter()

            datasets <- values$datasets

            if (purrr::is_empty(filter_range) || length(filter_range) != 2) {
                return(datasets)
            }

            datasets[datasets$row_count >= filter_range[1] & datasets$row_count <= filter_range[2], ]
        })

        # Open upload modal
        observeEvent(input$open_upload, {
            trigger("show_upload_modal")
        })

        # Handle dataset click - navigate to dataset page
        observeEvent(input$dataset_click, {
            dataset_id <- input$dataset_click
            # Store selected dataset ID in session for the dataset page to read
            session$userData$selected_dataset_id <- dataset_id
            if (!is.null(nav_select_callback)) {
                nav_select_callback("dataset")
            }
        })

        # Handle dataset delete
        observeEvent(input$dataset_delete, {
            dataset_id <- input$dataset_delete

            showModal(modalDialog(
                title = tr("Confirm Delete"),
                p(
                    class = "i18n",
                    `data-key` = "Are you sure you want to delete this dataset?",
                    tr("Are you sure you want to delete this dataset?")
                ),
                footer = tagList(
                    actionButton(
                        ns("confirm_delete"),
                        tr("Delete"),
                        class = "btn-danger i18n",
                        `data-key` = "Delete"
                    ),
                    modalButton(tr("Cancel"))
                ),
                easyClose = TRUE
            ))

            # Store the dataset ID to delete
            values$pending_delete_id <- dataset_id
        })

        # Confirm delete
        observeEvent(input$confirm_delete, {
            req(values$pending_delete_id)

            tryCatch(
                {
                    db_delete_dataset(pool, values$pending_delete_id)
                    values$pending_delete_id <- NULL
                    trigger("refresh_datasets")
                    removeModal()

                    shinyWidgets::show_toast(
                        title = tr("Dataset deleted successfully"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    shinyWidgets::show_toast(
                        title = paste(tr("Error deleting dataset:"), e$message),
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })

        # ------ OUTPUT --------------------------------------------------------

        output$dataset_count <- renderText({
            if (purrr::is_empty(values$datasets)) {
                return("0")
            }
            nrow(values$datasets)
        })

        output$dataset_list <- renderUI({
            datasets <- filtered_datasets()

            if (purrr::is_empty(datasets) || nrow(datasets) == 0) {
                return(
                    div(
                        class = "empty-state",
                        bsicons::bs_icon("folder2-open", size = "3rem"),
                        p(
                            class = "i18n",
                            `data-key` = "No datasets match the current filter",
                            tr("No datasets match the current filter")
                        )
                    )
                )
            }

            # Render each dataset row using HTML template
            dataset_rows <- lapply(seq_len(nrow(datasets)), \(i) {
                row <- datasets[i, ]
                htmltools::htmlTemplate(
                    "www/html/dataset_row.html",
                    id = row$id,
                    name = row$name,
                    row_count = format(row$row_count, big.mark = ","),
                    col_count = row$col_count,
                    ns = ns("")
                )
            })

            tagList(dataset_rows)
        })
    })
}
