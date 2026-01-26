# Dataset row server module
# Handles display and actions (edit, delete, download) for a single dataset row
#
# @param row_id Reactive returning the dataset ID for this row
dataset_row_server <- function(
    id,
    all_datasets,
    row_id,
    on_click = NULL,
    nav_select_callback = NULL
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Gate: stop all logic if this row no longer exists in data
        my_data <- reactive(label = paste0("row_", id, "_data"), {
            data <- all_datasets()
            rid <- row_id()
            req(rid)
            req(rid %in% data$id)
            data[data$id == rid, ]
        })

        # ------ CLICK (row navigation) ----------------------------------------
        observeEvent(input$row_click, label = paste0("row_", id, "_click"), {
            req(on_click) # Only from the home page
            on_click(row_id())
        })

        # ------ EDIT ----------------------------------------------------------
        observeEvent(input$edit, label = paste0("row_", id, "_edit"), {
            req(my_data())
            session$userData$edit_dataset_id <- row_id()
            session$userData$edit_dataset_name <- my_data()$name
            trigger("show_edit_dataset_modal")
        })

        # ------ DELETE --------------------------------------------------------
        observeEvent(input$delete, label = paste0("row_", id, "_delete"), {
            req(can("delete:dataset"))
            req(my_data())

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
        })

        observeEvent(
            input$confirm_delete,
            label = paste0("row_", id, "_confirm_delete"),
            {
                tryCatch(
                    {
                        db_delete_dataset(row_id())
                        removeModal()
                        trigger("refresh_datasets")
                        trigger("refresh_models")

                        # Navigate to home if callback provided (dataset page)
                        if (!is.null(nav_select_callback)) {
                            nav_select_callback("home")
                        }

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
            }
        )

        # ------ DOWNLOAD ------------------------------------------------------
        output$download <- downloadHandler(
            filename = function() {
                req(my_data())
                dataset_name <- my_data()$name %||% "dataset"
                safe_name <- gsub("[^a-zA-Z0-9_-]", "_", dataset_name)
                paste0(safe_name, "_", format(Sys.Date(), "%Y%m%d"), ".csv")
            },
            content = function(file) {
                req(my_data())
                dataset_row <- db_get_dataset(row_id())
                req(dataset_row)
                data <- db_parse_dataset_data(dataset_row$data)
                write.csv(data, file, row.names = FALSE)
                log_info("Dataset '{my_data()$name}' downloaded")
            }
        )

        # ------ OUTPUT --------------------------------------------------------
        output$name <- renderText({
            req(my_data())
            my_data()$name
        })

        output$created_at <- renderText({
            req(my_data())
            format(as.Date(my_data()$created_at), "%Y-%m-%d")
        })

        output$size <- renderText({
            req(my_data())
            paste0(
                format(my_data()$row_count, big.mark = ","),
                " rows × ",
                my_data()$col_count,
                " cols"
            )
        })
    })
}
