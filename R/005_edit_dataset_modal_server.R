# Own the rename modal and return open(dataset_id, dataset_name) for other modules to call.
# server.R passes this callback to the dataset actions. Each call opens the modal,
# including repeated edits of the same dataset (a reactiveVal would ignore an unchanged ID).
edit_dataset_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(
            pending_rename_id = NULL
        )

        open <- function(dataset_id, dataset_name) {
            values$pending_rename_id <- dataset_id
            showModal(edit_dataset_modal_ui(ns, current_name = dataset_name))
        }

        # Confirm rename
        observeEvent(input$confirm_rename, label = "edit_dataset_confirm_rename", {
            req(values$pending_rename_id)
            new_name <- trimws(input$new_dataset_name)

            # Validate name
            if (purrr::is_empty(new_name) || !nzchar(new_name)) {
                show_toast(
                    title = tr("Dataset name cannot be empty"),
                    type = "error",
                    timer = 3000,
                    position = "bottom-end"
                )
                return()
            }

            tryCatch(
                {
                    db_update_dataset_name(
                        values$pending_rename_id,
                        new_name,
                        purrr::pluck(session$userData$user, "id")
                    )
                    values$pending_rename_id <- NULL
                    removeModal()
                    trigger("refresh_datasets")

                    show_toast(
                        title = tr("Dataset renamed successfully"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    show_toast(
                        title = paste(tr("Error renaming dataset:"), e$message),
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })

        return(list(open = open))
    })
}
