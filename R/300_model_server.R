model_server <- function(
    id,
    selected_dataset_id = reactive(NULL),
    selected_model_id = reactive(NULL),
    active_page = reactive(NULL),
    r = NULL
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(
            dataset = NULL,
            data = NULL,
            fitted_model = NULL,
            metrics = NULL,
            loaded_model_id = NULL # Track if current model is saved (for delete)
        )

        has_data <- reactive(!purrr::is_empty(values$data), label = "model_has_data")
        has_model <- reactive(!purrr::is_empty(values$fitted_model), label = "model_has_fitted")

        # ------ REACTIVE ------------------------------------------------------

        # Load dataset when selection changes (ignoreInit = FALSE for bookmark restoration)
        observeEvent(
            selected_dataset_id(),
            label = "model_load_dataset",
            ignoreNULL = FALSE,
            {
                dataset_id <- selected_dataset_id()

                # Clear previous model when dataset changes
                values$fitted_model <- NULL
                values$metrics <- NULL
                values$loaded_model_id <- NULL
                shinyjs::disable("save_btn")
                shinyjs::disable("delete_btn")
                shinyjs::hide("results_section")

                if (purrr::is_empty(dataset_id)) {
                    log_debug("[MODEL] No dataset selected, clearing data")
                    values$dataset <- NULL
                    values$data <- NULL
                    return()
                }

                # Fetch dataset from DB
                dataset_row <- db_get_dataset(dataset_id)
                if (purrr::is_empty(dataset_row)) {
                    log_warn("[MODEL] Dataset {dataset_id} not found in DB")
                    values$dataset <- NULL
                    values$data <- NULL
                    return()
                }

                # Parse JSON data to data frame
                tryCatch(
                    {
                        values$data <- db_parse_dataset_data(dataset_row$data)
                        values$dataset <- dataset_row
                    },
                    error = \(e) {
                        log_error("[MODEL] Error parsing dataset: {e$message}")
                        values$data <- NULL
                        values$dataset <- NULL
                        shinyWidgets::show_toast(
                            title = paste(tr("Error parsing dataset:"), e$message),
                            type = "error",
                            timer = 5000,
                            position = "bottom-end"
                        )
                    }
                )
            }
        )

        # Load model when selected from dropdown (only when on model page and data loaded)
        observeEvent(
            list(selected_model_id(), values$data),
            label = "model_load_saved",
            {
                req(identical(active_page(), "model"))
                req(values$data) # Wait for dataset to load first
                model_id <- selected_model_id()
                req(!is.null(model_id), !is.na(model_id))
                req(!identical(model_id, values$loaded_model_id))
                model_load_saved(model_id, session, values, data = values$data)
            }
        )

        # Load pre-selected model when navigating TO model page
        observeEvent(active_page(), label = "model_page_enter", ignoreInit = TRUE, {
            req(identical(active_page(), "model"))
            req(values$data) # Wait for dataset to load first
            req(is.null(values$fitted_model)) # Skip if already loaded
            model_id <- selected_model_id()
            req(!is.null(model_id), !is.na(model_id))
            model_load_saved(model_id, session, values, data = values$data, silent_fail = TRUE)
        })

        # ------ MODEL FITTING (ASYNC) -----------------------------------------

        fit_task <- ExtendedTask$new(function(data, formula_str) {
            mirai::mirai(
                task_fn(data, formula_str, log_fn, metrics_fn),
                data = data,
                formula_str = formula_str,
                log_fn = make_mirai_logger("MODEL"),
                metrics_fn = model_compute_metrics,
                task_fn = model_fit_task
            )
        }) |>
            bslib::bind_task_button("fit_btn")

        # Trigger fit when button is clicked
        observeEvent(input$fit_btn, label = "model_fit_click", {
            req(has_data())
            req(nzchar(trimws(input$equation)))
            fit_task$invoke(values$data, input$equation)
        })

        # Handle fit result
        observeEvent(fit_task$result(), label = "model_fit_result", {
            result <- fit_task$result()

            if (!result$success) {
                shinyWidgets::show_toast(
                    title = tr("Model fitting failed"),
                    text = result$message,
                    type = "error",
                    timer = 5000,
                    position = "bottom-end"
                )
                values$fitted_model <- NULL
                values$metrics <- NULL
                values$loaded_model_id <- NULL
                shinyjs::disable("save_btn")
                shinyjs::disable("delete_btn")
                shinyjs::hide("results_section")
                return()
            }

            # Store fitted model and metrics
            values$fitted_model <- result$model
            values$metrics <- list(
                r_squared = result$r_squared,
                rmse = result$rmse,
                aic = result$aic,
                summary_text = result$summary_text
            )
            values$loaded_model_id <- NULL # New fit, not saved yet

            # Enable save button and show results
            shinyjs::enable("save_btn")
            shinyjs::disable("delete_btn") # Can't delete unsaved model
            shinyjs::show("results_section")

            shinyWidgets::show_toast(
                title = tr("Model fitted successfully"),
                type = "success",
                timer = 3000,
                position = "bottom-end"
            )
        })

        # ------ SAVE MODEL ----------------------------------------------------

        observeEvent(input$save_btn, label = "model_save_click", {
            req(has_model())

            user_id <- purrr::pluck(session$userData$user, "id")
            req(user_id)
            req(selected_dataset_id())

            tryCatch(
                {
                    model_id <- db_upsert_model(
                        user_id = user_id,
                        dataset_id = selected_dataset_id(),
                        formula = input$equation,
                        model_obj = values$fitted_model
                    )

                    values$loaded_model_id <- model_id
                    shinyjs::enable("delete_btn")

                    # Update shared state so sidebar dropdown syncs to saved model
                    r$selected_model_id <- model_id

                    # Trigger refresh for sidebar model dropdown
                    trigger("refresh_models")

                    shinyWidgets::show_toast(
                        title = tr("Model saved"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    shinyWidgets::show_toast(
                        title = tr("Error saving model"),
                        text = e$message,
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })

        # ------ DELETE MODEL -----------------------------------------------------

        observeEvent(input$delete_btn, label = "model_delete_click", {
            req(values$loaded_model_id)

            tryCatch(
                {
                    db_delete_model(values$loaded_model_id)

                    # Clear state
                    values$fitted_model <- NULL
                    values$metrics <- NULL
                    values$loaded_model_id <- NULL
                    updateTextInput(session, "equation", value = "")
                    shinyjs::disable("save_btn")
                    shinyjs::disable("delete_btn")
                    shinyjs::hide("results_section")

                    # Trigger refresh for sidebar model dropdown
                    trigger("refresh_models")

                    shinyWidgets::show_toast(
                        title = tr("Model deleted"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    shinyWidgets::show_toast(
                        title = tr("Error deleting model"),
                        text = e$message,
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })

        # ------ OUTPUT --------------------------------------------------------

        output$r_squared <- renderText({
            req(values$metrics)
            sprintf("%.4f", values$metrics$r_squared)
        })

        output$rmse <- renderText({
            req(values$metrics)
            sprintf("%.4f", values$metrics$rmse)
        })

        output$aic <- renderText({
            req(values$metrics)
            if (is.na(values$metrics$aic)) {
                return("N/A")
            }
            sprintf("%.2f", values$metrics$aic)
        })

        output$summary <- renderPrint({
            req(values$metrics)
            cat(values$metrics$summary_text)
        })

        output$available_vars <- renderUI({
            req(has_data())
            vars <- setdiff(colnames(values$data), "X") # Exclude rownames column
            tags$small(
                class = "text-muted d-block mt-2",
                tags$strong(tr("Available variables:")),
                " ",
                paste(vars, collapse = ", ")
            )
        })

        # Show/hide empty state based on data presence
        observe(shinyjs::toggle("empty_state", condition = !has_data()), label = "model_empty_toggle")
    })
}
