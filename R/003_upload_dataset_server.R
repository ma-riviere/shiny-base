upload_dataset_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Size limits
        MAX_FILE_SIZE_MB <- 10
        MAX_ROWS <- 100000

        values <- reactiveValues(
            error = NULL,
            status = NULL
        )

        # ------ REACTIVE ------------------------------------------------------

        # Show modal when triggered
        on("show_upload_modal", {
            showModal(upload_dataset_modal_ui(ns))
        })

        # Enable/disable upload button based on file selection
        observe({
            shinyjs::toggleState("upload_btn", condition = !is.null(input$file))
        })

        # Auto-fill dataset name from filename when file is selected
        observeEvent(input$file, {
            req(input$file)
            # Only auto-fill if the dataset name is empty
            current_name <- trimws(input$dataset_name)
            if (purrr::is_empty(current_name) || current_name == "") {
                filename <- input$file$name
                # Remove extension to get base name
                basename_no_ext <- tools::file_path_sans_ext(filename)
                updateTextInput(session, "dataset_name", value = basename_no_ext)
            }
        })

        # Validate and parse uploaded file
        parsed_data <- reactive({
            req(input$file)

            file_info <- input$file
            file_path <- file_info$datapath
            file_size_mb <- file_info$size / (1024 * 1024)

            # Check file size
            if (file_size_mb > MAX_FILE_SIZE_MB) {
                values$error <- sprintf(
                    tr("File too large. Maximum size is %dMB, your file is %.1fMB"),
                    MAX_FILE_SIZE_MB,
                    file_size_mb
                )
                return(NULL)
            }

            # Try to parse CSV
            tryCatch(
                {
                    data <- read.csv(file_path, stringsAsFactors = FALSE)

                    # Check row count
                    if (nrow(data) > MAX_ROWS) {
                        values$error <- sprintf(
                            tr("Too many rows. Maximum is %s rows, your file has %s rows"),
                            format(MAX_ROWS, big.mark = ","),
                            format(nrow(data), big.mark = ",")
                        )
                        return(NULL)
                    }

                    values$error <- NULL
                    values$status <- sprintf(
                        tr("Ready to upload: %s rows, %s columns"),
                        format(nrow(data), big.mark = ","),
                        ncol(data)
                    )
                    return(data)
                },
                error = \(e) {
                    values$error <- paste(tr("Error parsing CSV:"), e$message)
                    return(NULL)
                }
            )
        })

        # Handle upload button click
        observeEvent(input$upload_btn, {
            user_id <- purrr::pluck(session$userData$user, "id")
            req(user_id)

            dataset_name <- trimws(input$dataset_name)
            data <- parsed_data()

            # Validate dataset name
            if (purrr::is_empty(dataset_name) || dataset_name == "") {
                values$error <- tr("Please enter a dataset name")
                return()
            }

            # Validate data
            if (purrr::is_empty(data)) {
                values$error <- tr("Please select a valid CSV file")
                return()
            }

            # Save to database
            tryCatch(
                {
                    db_create_dataset(pool, user_id, dataset_name, data)
                    values$error <- NULL
                    values$status <- NULL
                    removeModal()
                    trigger("refresh_datasets")

                    shinyWidgets::show_toast(
                        title = tr("Dataset uploaded successfully"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    values$error <- paste(tr("Error saving dataset:"), e$message)
                }
            )
        })

        # ------ OUTPUT --------------------------------------------------------

        # Display selected file info
        output$selected_file_ui <- renderUI({
            req(input$file)
            div(
                class = "selected-file-info",
                bsicons::bs_icon("file-earmark-text"),
                span(class = "filename", input$file$name)
            )
        })

        output$upload_status <- renderUI({
            if (!purrr::is_empty(values$error)) {
                div(
                    class = "alert alert-danger",
                    role = "alert",
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
