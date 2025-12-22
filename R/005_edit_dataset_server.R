# Edit dataset server module (handles rename modal logic)
# Triggered via gargoyle event with dataset_id stored in session$userData
edit_dataset_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(
            pending_rename_id = NULL
        )

        # Show modal when triggered
        on("show_edit_dataset_modal", {
            dataset_id <- session$userData$edit_dataset_id
            dataset_name <- session$userData$edit_dataset_name
            req(dataset_id, dataset_name)

            values$pending_rename_id <- dataset_id
            showModal(edit_dataset_modal_ui(ns, current_name = dataset_name))
        })

        # Confirm rename
        observeEvent(input$confirm_rename, {
            req(values$pending_rename_id)
            new_name <- trimws(input$new_dataset_name)

            # Validate name
            if (purrr::is_empty(new_name) || new_name == "") {
                shinyWidgets::show_toast(
                    title = tr("Dataset name cannot be empty"),
                    type = "error",
                    timer = 3000,
                    position = "bottom-end"
                )
                return()
            }

            tryCatch(
                {
                    db_update_dataset_name(pool, values$pending_rename_id, new_name)
                    values$pending_rename_id <- NULL
                    removeModal()
                    trigger("refresh_datasets")

                    shinyWidgets::show_toast(
                        title = tr("Dataset renamed successfully"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    shinyWidgets::show_toast(
                        title = paste(tr("Error renaming dataset:"), e$message),
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })
    })
}
