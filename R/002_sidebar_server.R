# Sidebar server module
# Manages dataset/model selection dropdowns and filters.
# Section visibility is handled by conditionalPanel in sidebar_ui.R (browser-side).
#
# @param r Shared reactiveValues for cross-module state. Expected fields:
#   - selected_dataset_id: Dataset ID selected from home page row click (read/write)
#   - selected_model_id: Model ID selected from model dropdown (read/write)
sidebar_server <- function(id, r) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns
        values <- reactiveValues(
            user_datasets = NULL,
            user_models = NULL,
            row_count_filter = c(0, 100000),
            age_filter = c(Sys.Date() - 365, Sys.Date()),
            prev_max_rows = NULL # Track previous max to detect actual changes
        )

        # ------ SHARED STATE SYNC ---------------------------------------------

        # Sync dropdown FROM shared state (when home page sets r$selected_dataset_id)
        observeEvent(
            r$selected_dataset_id,
            {
                req(r$selected_dataset_id)
                updateSelectInput(session, "selected_dataset", selected = as.character(r$selected_dataset_id))
            },
            ignoreNULL = TRUE,
            ignoreInit = TRUE,
            label = "sidebar_sync_shared_to_dropdown"
        )

        # Sync dropdown TO shared state (when user changes dropdown)
        observeEvent(
            input$selected_dataset,
            {
                if (purrr::is_empty(input$selected_dataset) || !nzchar(input$selected_dataset)) {
                    r$selected_dataset_id <- NULL
                } else {
                    r$selected_dataset_id <- as.integer(input$selected_dataset)
                }
            },
            label = "sidebar_sync_dropdown_to_shared"
        )

        # Sync model dropdown FROM shared state
        observeEvent(
            r$selected_model_id,
            {
                req(r$selected_model_id)
                updateSelectInput(session, "selected_model", selected = as.character(r$selected_model_id))
            },
            ignoreNULL = TRUE,
            ignoreInit = TRUE,
            label = "sidebar_sync_model_shared_to_dropdown"
        )

        # Sync model dropdown TO shared state
        observeEvent(
            input$selected_model,
            {
                if (purrr::is_empty(input$selected_model) || !nzchar(input$selected_model)) {
                    r$selected_model_id <- NULL
                } else {
                    r$selected_model_id <- as.integer(input$selected_model)
                }
            },
            label = "sidebar_sync_model_dropdown_to_shared"
        )

        # ------ REACTIVE ------------------------------------------------------

        # Load user datasets for dropdown (re-runs when refresh_datasets is triggered)
        observeEvent(
            watch("refresh_datasets"),
            {
                user_id <- purrr::pluck(session$userData$user, "id")
                req(user_id)

                datasets <- db_get_user_datasets(user_id)
                values$user_datasets <- datasets

                # Preserve selection: shared state > restored bookmark > first dataset
                current_selection <- as.integer(
                    r$selected_dataset_id %||% get_restored_input("selected_dataset")
                )

                if (purrr::is_empty(datasets) || nrow(datasets) == 0) {
                    updateSelectInput(session, "selected_dataset", choices = c("No datasets" = ""), selected = "")
                } else {
                    choices <- setNames(datasets$id, datasets$name)
                    new_selected <- if (isTRUE(current_selection %in% datasets$id)) {
                        current_selection
                    } else {
                        datasets$id[1]
                    }
                    updateSelectInput(
                        session,
                        "selected_dataset",
                        choices = choices,
                        selected = new_selected
                    )
                    # Also update shared state
                    r$selected_dataset_id <- as.integer(new_selected)
                }
            },
            ignoreInit = FALSE,
            label = "sidebar_refresh_datasets"
        )

        # Track filter changes
        observeEvent(
            input$row_count_filter,
            {
                values$row_count_filter <- input$row_count_filter
            },
            label = "sidebar_filter_row_count"
        )

        observeEvent(
            input$age_filter,
            {
                values$age_filter <- input$age_filter
            },
            label = "sidebar_filter_age"
        )

        # Update slider range when datasets are added or deleted
        observeEvent(
            watch("refresh_datasets"),
            {
                req(values$user_datasets)
                if (nrow(values$user_datasets) > 0) {
                    # Max is always based on ALL user datasets
                    max_rows <- max(values$user_datasets$row_count, na.rm = TRUE)

                    # Only reset value if this is the first load OR if max_rows actually changed
                    # (e.g., dataset added/deleted), not when user manually adjusts the slider
                    prev_max <- values$prev_max_rows
                    max_changed <- is.null(prev_max) || prev_max != max_rows

                    current_value <- input$row_count_filter
                    is_default <- purrr::is_empty(current_value) ||
                        identical(current_value, c(0L, 100000L))

                    if (is_default || max_changed) {
                        # Calculate reasonable step: 1 for small datasets, ~1% of max for large
                        step <- if (max_rows <= 200) 1 else max(1, round(max_rows / 100))
                        updateSliderInput(
                            session,
                            "row_count_filter",
                            min = 0,
                            max = max_rows,
                            value = c(0, max_rows),
                            step = step
                        )
                    } else {
                        # Just update the range limits, keep the current value
                        step <- if (max_rows <= 200) 1 else max(1, round(max_rows / 100))
                        updateSliderInput(
                            session,
                            "row_count_filter",
                            min = 0,
                            max = max_rows,
                            step = step
                        )
                    }

                    # Remember the current max for next comparison
                    values$prev_max_rows <- max_rows
                }
            },
            priority = 0,
            label = "sidebar_update_slider_range"
        )

        # Load models for selected dataset
        observeEvent(
            list(watch("refresh_models"), r$selected_dataset_id),
            {
                user_id <- purrr::pluck(session$userData$user, "id")
                dataset_id <- r$selected_dataset_id

                if (purrr::is_empty(user_id) || purrr::is_empty(dataset_id)) {
                    values$user_models <- NULL
                    updateSelectInput(session, "selected_model", choices = c("No models" = ""), selected = "")
                    r$selected_model_id <- NULL
                    return()
                }

                models <- db_get_models_for_dataset(user_id, dataset_id)
                values$user_models <- models

                # Preserve selection: shared state > restored bookmark > none
                current_model <- as.integer(r$selected_model_id %||% get_restored_input("selected_model"))

                if (purrr::is_empty(models) || nrow(models) == 0) {
                    updateSelectInput(session, "selected_model", choices = c("No models" = ""), selected = "")
                    r$selected_model_id <- NULL
                } else {
                    choices <- c("Select a model" = "", setNames(models$id, models$formula))
                    new_selected <- if (isTRUE(current_model %in% models$id)) as.character(current_model) else ""
                    updateSelectInput(session, "selected_model", choices = choices, selected = new_selected)
                    if (!nzchar(new_selected)) r$selected_model_id <- NULL
                }
            },
            ignoreInit = FALSE,
            label = "sidebar_refresh_models"
        )

        # Note: Section visibility is handled by conditionalPanel in sidebar_ui.R
        # based on input.nav value (runs in browser, no server round-trip needed)

        return(values)
    })
}
