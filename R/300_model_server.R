# Model page server module
# Handles async model fitting, saving, and deletion.
#
# @param selected_dataset_id reactiveVal for currently selected dataset ID (read-only here)
# @param active_page Reactive for the currently active nav page
model_server <- function(
    id,
    selected_dataset_id = reactiveVal(NULL),
    active_page = reactive(NULL)
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Currently selected saved-model id. Module-local state, mirrored to the
        # bookmarkable `selected_model` input by the sync observer below.
        selected_model_id <- reactiveVal(NULL)

        values <- reactiveValues(
            dataset = NULL,
            data = NULL,
            fitted_model = NULL,
            metrics = NULL,
            loaded_model_id = NULL # Track if current model is saved (for delete)
        )

        has_data <- reactive(
            !purrr::is_empty(values$data),
            label = "model_has_data"
        )
        has_model <- reactive(
            !purrr::is_empty(values$fitted_model),
            label = "model_has_fitted"
        )

        # Saved models for the current dataset: one source shared by the picker
        # render and the id-validation guard. Refreshes on save/delete.
        user_models <- reactive(label = "model_user_models", {
            watch("refresh_models")
            user_id <- purrr::pluck(session$userData$user, "id")
            req(user_id, selected_dataset_id())
            db_get_models_for_dataset(user_id, selected_dataset_id())
        })

        # ------ REACTIVE ------------------------------------------------------

        # Load dataset when selection changes (ignoreInit = FALSE for bookmark restoration)
        observeEvent(
            selected_dataset_id(),
            label = "model_load_dataset",
            ignoreNULL = FALSE,
            {
                dataset_id <- selected_dataset_id()

                # Clear previous model and selection when dataset changes
                # (the saved-models table is scoped to the current dataset)
                values$fitted_model <- NULL
                values$metrics <- NULL
                values$loaded_model_id <- NULL
                selected_model_id(NULL)
                updateTextInput(session, "equation", value = "")
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
                        show_toast(
                            title = paste(tr("Error parsing dataset:"), e$message),
                            type = "error",
                            timer = 5000,
                            position = "bottom-end"
                        )
                    }
                )
            }
        )

        # Load model when selection changes (only when on model page and data loaded)
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
            model_load_saved(
                model_id,
                session,
                values,
                data = values$data,
                silent_fail = TRUE
            )
        })

        # ------ MODEL FITTING (ASYNC) -----------------------------------------

        fit_task <- ExtendedTask$new(function(data, formula) {
            mirai::mirai(
                task_fn(data, formula, log_fn, metrics_fn),
                data = data,
                formula = formula,
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

            # SECURITY: formulas execute code during model.frame(), so the raw
            # equation string never reaches as.formula()/lm() (see helpers_formula.R)
            formula_obj <- tryCatch(
                validate_formula(input$equation, colnames(values$data)),
                error = \(e) {
                    show_toast(
                        title = tr("Invalid formula"),
                        text = e$message,
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                    # No task invoked: release the task button manually
                    bslib::update_task_button("fit_btn", state = "ready")
                    NULL
                }
            )
            req(!is.null(formula_obj))
            fit_task$invoke(values$data, formula_obj)
        })

        # Handle fit result
        observeEvent(fit_task$result(), label = "model_fit_result", {
            result <- fit_task$result()

            if (!result$success) {
                show_toast(
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
            selected_model_id(NULL) # Unsaved fit: no saved model is selected

            # Enable save button and show results
            shinyjs::enable("save_btn")
            shinyjs::disable("delete_btn") # Can't delete unsaved model
            shinyjs::show("results_section")

            show_toast(
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

                    # Select the saved model (highlights its row; the sync
                    # observer mirrors it to the bookmarkable input)
                    selected_model_id(model_id)

                    # Refresh the saved-models picker
                    trigger("refresh_models")

                    show_toast(
                        title = tr("Model saved"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    show_toast(
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

                    # Clear state (clearing the selection also clears the
                    # bookmarkable input via the sync observer)
                    values$fitted_model <- NULL
                    values$metrics <- NULL
                    values$loaded_model_id <- NULL
                    selected_model_id(NULL)
                    updateTextInput(session, "equation", value = "")
                    shinyjs::disable("save_btn")
                    shinyjs::disable("delete_btn")
                    shinyjs::hide("results_section")

                    # Refresh the saved-models picker
                    trigger("refresh_models")

                    show_toast(
                        title = tr("Model deleted"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    show_toast(
                        title = tr("Error deleting model"),
                        text = e$message,
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })

        # ------ SAVED MODELS PICKER -------------------------------------------
        # Compact click-to-select list (rendered into the sidebar) of this
        # dataset's saved models. Demonstrates the "one observer for all rows"
        # pattern (see set_input_js() in helpers_tables.R) with two flavours:
        #   - Select: clicking a row sets a STABLE value input (`selected_model`),
        #             deduplicated, so the selection bookmarks/restores like any input.
        #   - Delete: a per-row ACTION button (`model_action_delete` = {id} with
        #             priority 'event', so repeat clicks re-fire). It sits OUTSIDE
        #             the clickable area (sibling, not child), so clicking it does
        #             not select; bookmark-excluded.

        output$saved_models <- renderUI({
            req(has_data())
            models <- user_models()

            if (purrr::is_empty(models) || nrow(models) == 0) {
                return(p(
                    class = "text-muted small fst-italic mb-0 i18n",
                    `data-key` = "No saved models for this dataset",
                    tr("No saved models for this dataset")
                ))
            }

            # One delete button per row
            delete_btns <- create_table_action_button(
                ns("model_action_delete"),
                models$id,
                icon = "trash",
                title = tr("Delete model"),
                class = "model-picker-delete"
            )

            sel_id <- selected_model_id() %||% -1L
            rows <- lapply(seq_len(nrow(models)), function(i) {
                select_js <- set_input_js(ns("selected_model"), models$id[i])
                div(
                    class = paste("model-picker-row", if (isTRUE(models$id[i] == sel_id)) "selected"),
                    div(
                        class = "model-picker-select",
                        role = "button",
                        tabindex = "0",
                        onclick = select_js,
                        onkeydown = sprintf(
                            "if(event.key==='Enter'||event.key===' '){event.preventDefault();%s}",
                            select_js
                        ),
                        span(class = "model-picker-formula", models$formula[i])
                    ),
                    HTML(delete_btns[i])
                )
            })

            div(class = "model-picker", rows)
        })

        # Guard: a model id from the client (row click) or a restored bookmark must
        # be one of the current dataset's models before we act on it (server-side
        # validation; never trust client-supplied ids).
        model_belongs <- function(model_id) {
            !is.na(model_id) && isTRUE(model_id %in% user_models()$id)
        }

        # Select a model when its row is clicked. `selected_model` is a stable
        # value input; setting the shared state lets model_load_saved load it.
        observeEvent(input$selected_model, label = "model_table_select", {
            req(nzchar(input$selected_model))
            model_id <- as.integer(input$selected_model)
            req(model_belongs(model_id))
            selected_model_id(model_id)
        })

        # Keep the bookmarkable `selected_model` input in sync with the shared
        # state, so the selection survives bookmarking no matter how it changed
        # (row click, save, fit, delete, restore).
        observeEvent(
            selected_model_id(),
            ignoreNULL = FALSE,
            ignoreInit = TRUE,
            label = "model_sync_selection_input",
            {
                shinyjs::runjs(sprintf(
                    "Shiny.setInputValue('%s', '%s')",
                    ns("selected_model"),
                    selected_model_id() %||% ""
                ))
            }
        )

        # Restore the bookmarked selection once the dataset's data is available.
        # The selection lives in a shared reactiveVal (not a native input), so on
        # restore we seed it from the captured bookmark (mirrors the dataset path).
        observeEvent(values$data, label = "model_restore_selection", once = TRUE, {
            restored <- get_restored_input("selected_model")
            req(!is.null(restored), is.null(selected_model_id()))
            model_id <- as.integer(restored)
            if (model_belongs(model_id)) {
                selected_model_id(model_id)
            } else {
                # Drop a stale/deleted bookmarked id so it isn't re-persisted.
                shinyjs::runjs(sprintf("Shiny.setInputValue('%s', '')", ns("selected_model")))
            }
        })

        # Delete a model when any row's "Delete" button is clicked (single observer).
        observeEvent(input$model_action_delete, label = "model_table_delete", {
            model_id <- as.integer(input$model_action_delete$id)
            req(model_belongs(model_id))

            tryCatch(
                {
                    db_delete_model(model_id)

                    # If the deleted model is the one loaded in the editor, clear it
                    if (isTRUE(model_id == values$loaded_model_id)) {
                        values$fitted_model <- NULL
                        values$metrics <- NULL
                        values$loaded_model_id <- NULL
                        updateTextInput(session, "equation", value = "")
                        shinyjs::disable("save_btn")
                        shinyjs::disable("delete_btn")
                        shinyjs::hide("results_section")
                    }
                    # Clearing the selection also clears the bookmarkable input
                    # (via the sync observer), so a deleted id is not restored.
                    if (isTRUE(model_id == selected_model_id())) {
                        selected_model_id(NULL)
                    }

                    trigger("refresh_models")

                    show_toast(
                        title = tr("Model deleted"),
                        type = "success",
                        timer = 3000,
                        position = "bottom-end"
                    )
                },
                error = \(e) {
                    show_toast(
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
        observe(
            shinyjs::toggle("empty_state", condition = !has_data()),
            label = "model_empty_toggle"
        )
    })
}
