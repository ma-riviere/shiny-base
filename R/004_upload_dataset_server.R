upload_dataset_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Size limits
        MAX_FILE_SIZE_MB <- 10
        MAX_ROWS <- 100000

        values <- reactiveValues(
            error = NULL,
            status = NULL,
            parsed_files = list()
        )

        # ------ VALIDATION ----------------------------------------------------

        iv <- shinyvalidate::InputValidator$new()
        iv$add_rule("file", sv_file_required(message = tr("Please select at least one CSV file")))
        iv$add_rule("file", sv_file_extension(c("csv"), message = tr("Only CSV files are allowed")))
        iv$add_rule("file", sv_file_size(MAX_FILE_SIZE_MB))
        iv$enable()

        # ------ REACTIVE ------------------------------------------------------

        # Show modal when triggered
        on("show_upload_modal", {
            showModal(upload_dataset_modal_ui(ns))
        })

        # Enable/disable upload button based on validation state
        observe({
            shinyjs::toggleState("upload_btn", condition = iv$is_valid())
        }) |>
            bindEvent(iv$is_valid())

        # Parse uploaded files and validate
        observeEvent(input$file, {
            req(input$file)
            req(iv$is_valid())

            parsed_list <- list()
            errors <- character()
            total_rows <- 0
            total_cols <- 0

            for (i in seq_len(nrow(input$file))) {
                file_info <- input$file[i, ]
                file_path <- file_info$datapath
                filename <- file_info$name
                basename_no_ext <- tools::file_path_sans_ext(filename)

                tryCatch(
                    {
                        data <- read.csv(file_path, stringsAsFactors = FALSE)

                        # Check row count
                        if (nrow(data) > MAX_ROWS) {
                            errors <- c(
                                errors,
                                tr(
                                    "%s: Too many rows (max %s, has %s)",
                                    filename,
                                    format(MAX_ROWS, big.mark = ","),
                                    format(nrow(data), big.mark = ",")
                                )
                            )
                        } else {
                            parsed_list[[basename_no_ext]] <- list(
                                name = basename_no_ext,
                                data = data,
                                filename = filename
                            )
                            total_rows <- total_rows + nrow(data)
                            total_cols <- total_cols + ncol(data)
                        }
                    },
                    error = \(e) {
                        errors <- c(
                            errors,
                            tr("%s: Error parsing CSV - %s", filename, e$message)
                        )
                    }
                )
            }

            values$parsed_files <- parsed_list

            if (length(errors) > 0) {
                values$error <- paste(errors, collapse = "\n")
                values$status <- NULL
            } else {
                values$error <- NULL
                if (length(parsed_list) > 0) {
                    values$status <- tr(
                        "Ready to upload %s file(s)",
                        length(parsed_list)
                    )
                }
            }
        })

        # Handle upload button click
        observeEvent(input$upload_btn, {
            # Validation is handled by shinyvalidate, but double-check
            if (!iv$is_valid() || length(values$parsed_files) == 0) {
                return()
            }

            user_id <- purrr::pluck(session$userData$user, "id")
            req(user_id)

            # Upload each parsed file
            success_count <- 0
            error_count <- 0
            errors <- character()

            for (dataset_name in names(values$parsed_files)) {
                file_data <- values$parsed_files[[dataset_name]]

                tryCatch(
                    {
                        db_create_dataset(user_id, dataset_name, file_data$data)
                        success_count <- success_count + 1
                        log_info("Dataset '{dataset_name}' uploaded by user {user_id}")
                    },
                    error = \(e) {
                        error_count <- error_count + 1
                        errors <- c(
                            errors,
                            tr("%s: Error saving - %s", dataset_name, e$message)
                        )
                        log_error("Failed to save dataset {dataset_name}: {e$message}")
                    }
                )
            }

            # Clear state and close modal if all successful
            if (error_count == 0) {
                values$error <- NULL
                values$status <- NULL
                values$parsed_files <- list()
                removeModal()
                trigger("refresh_datasets")

                if (success_count == 1) {
                    msg <- tr("Dataset uploaded successfully")
                } else {
                    msg <- tr("%s datasets uploaded successfully", success_count)
                }

                shinyWidgets::show_toast(
                    title = msg,
                    type = "success",
                    timer = 3000,
                    position = "bottom-end"
                )
            } else {
                # Show errors
                values$error <- paste(errors, collapse = "\n")
                if (success_count > 0) {
                    trigger("refresh_datasets")
                    shinyWidgets::show_toast(
                        title = tr(
                            "%s of %s datasets uploaded",
                            success_count,
                            success_count + error_count
                        ),
                        type = "warning",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            }
        })

        # ------ OUTPUT --------------------------------------------------------

        # Display selected files info
        output$selected_file_ui <- renderUI({
            req(input$file)
            file_list <- lapply(seq_len(nrow(input$file)), \(i) {
                div(
                    class = "selected-file-info",
                    bsicons::bs_icon("file-earmark-text"),
                    span(class = "filename", input$file$name[i])
                )
            })
            tagList(file_list)
        })

        output$upload_status <- renderUI({
            if (!purrr::is_empty(values$error)) {
                div(
                    class = "alert alert-danger",
                    role = "alert",
                    style = "white-space: pre-line;",
                    values$error
                )
            } else if (!purrr::is_empty(values$status)) {
                div(
                    class = "alert alert-info",
                    role = "alert",
                    values$status
                )
            }
        })
    })
}
