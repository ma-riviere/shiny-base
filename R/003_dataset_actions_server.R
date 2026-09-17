# One instance per page handles edit/download/delete for every dataset row.
# Buttons send the dataset ID to a shared input for each action (see dataset_row_ui()).
# No per-row server is needed, so deleting rows leaves no unused observers behind.
#
# @param datasets Reactive data.frame of the datasets the host currently
#   displays (validates client-supplied ids, provides names).
# @param edit_dataset_callback Callback `function(dataset_id, dataset_name)` opening the
#   rename modal (returned by edit_dataset_modal_server()).
# @param nav_select_callback Optional; navigate home after a delete (explore page).
dataset_actions_server <- function(
    id,
    datasets,
    edit_dataset_callback,
    nav_select_callback = NULL
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # One slot per two-step action. The row button carries the dataset id (input$delete,
        # input$download); the second step (the modal's Confirm button, the hidden download link)
        # carries nothing. We keep the validated, typed id here between the two steps, and clear
        # it once used, so a replayed confirm does nothing (the browser is not trusted).
        # Plain state, nothing reacts to it: reactiveValues is just the usual home for module state.
        values <- reactiveValues(
            pending_delete_id = NULL,
            download_id = NULL
        )

        # Only accept IDs from the page's dataset list; DB calls also check ownership.
        # Match as strings: as.integer() warns on malformed input, fatal under shinytest2's warn = 2.
        # Return the server's row, including its correctly typed ID.
        dataset_from_id <- function(raw_id) {
            data <- datasets()
            row_idx <- match(as.character(raw_id), as.character(data$id))
            req(!is.na(row_idx))
            return(data[row_idx, ])
        }

        # ------ EDIT ----------------------------------------------------------
        observeEvent(input$edit, label = ns("edit"), {
            dataset <- dataset_from_id(input$edit)
            edit_dataset_callback(dataset$id, dataset$name)
        })

        # ------ DELETE --------------------------------------------------------
        observeEvent(input$delete, label = ns("delete"), {
            req(can("delete:dataset"))
            dataset <- dataset_from_id(input$delete)
            values$pending_delete_id <- dataset$id

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

        observeEvent(input$confirm_delete, label = ns("confirm_delete"), {
            req(values$pending_delete_id)
            tryCatch(
                {
                    db_delete_dataset(values$pending_delete_id, purrr::pluck(session$userData$user, "id"))
                    values$pending_delete_id <- NULL
                    removeModal()
                    trigger("refresh_datasets")
                    trigger("refresh_models")

                    # Navigate to home if callback provided (dataset page)
                    if (!is.null(nav_select_callback)) {
                        nav_select_callback("home")
                    }

                    show_toast(
                        title = tr("Dataset deleted successfully"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    show_toast(
                        title = paste(tr("Error deleting dataset:"), e$message),
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })

        # ------ DOWNLOAD ------------------------------------------------------
        # Two JS hops, one per direction. Browser -> R: the row button only carries the dataset id;
        # the click handler in www/js/app.js turns it into Shiny.setInputValue("<ns>-download", "<id>",
        # {priority: "event"}), which lands here as a string. R -> browser: a downloadHandler needs a
        # real <a> the browser navigates to, so we store the validated id, then click the ONE hidden
        # link of this page (dataset_actions_ui) from R; its handler reads values$download_id.
        observeEvent(input$download, label = ns("download"), {
            dataset <- dataset_from_id(input$download)
            values$download_id <- dataset$id
            # Native click: shinyjs::click() is a jQuery-triggered click, which
            # fires handlers but NOT the anchor's default navigation (no download)
            shinyjs::runjs(sprintf("document.getElementById('%s').click();", ns("download_file")))
        })

        output$download_file <- downloadHandler(
            filename = function() {
                dataset <- dataset_from_id(values$download_id)
                safe_name <- gsub("[^a-zA-Z0-9_-]", "_", dataset$name %||% "dataset")
                paste0(safe_name, "_", format(Sys.Date(), "%Y%m%d"), ".csv")
            },
            content = function(file) {
                req(values$download_id)
                dataset_row <- db_get_dataset(values$download_id, purrr::pluck(session$userData$user, "id"))
                req(dataset_row)
                data <- db_parse_dataset_data(dataset_row$data)
                write.csv(data, file, row.names = FALSE)
                log_info("Dataset '{dataset_row$name}' downloaded")
            }
        )
        # The link is display:none, so Shiny would suspend the output binding
        # and never populate its href; clicking would then do nothing
        outputOptions(output, "download_file", suspendWhenHidden = FALSE)
    })
}
