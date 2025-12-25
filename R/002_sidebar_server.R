sidebar_server <- function(id, active_page = reactive(NULL)) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns
        values <- reactiveValues(
            selected_dataset_id = NULL,
            user_datasets = NULL,
            row_count_filter = c(0, 100000),
            age_filter = c(Sys.Date() - 365, Sys.Date()),
            prev_max_rows = NULL # Track previous max to detect actual changes
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

                # Preserve current selection if it still exists
                current_selection <- values$selected_dataset_id

                # Update dropdown choices
                if (purrr::is_empty(datasets) || nrow(datasets) == 0) {
                    updateSelectInput(
                        session,
                        "selected_dataset",
                        choices = c("No datasets" = ""),
                        selected = ""
                    )
                } else {
                    choices <- setNames(datasets$id, datasets$name)
                    # Keep current selection if it still exists in the new list
                    new_selected <- if (!is.null(current_selection) && current_selection %in% datasets$id) {
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
                }
            },
            ignoreInit = FALSE
        )

        # Track selected dataset from dropdown
        observeEvent(input$selected_dataset, {
            if (purrr::is_empty(input$selected_dataset) || input$selected_dataset == "") {
                values$selected_dataset_id <- NULL
            } else {
                values$selected_dataset_id <- as.integer(input$selected_dataset)
            }
        })

        # Track filter changes
        observeEvent(input$row_count_filter, {
            values$row_count_filter <- input$row_count_filter
        })

        observeEvent(input$age_filter, {
            values$age_filter <- input$age_filter
        })

        # Update slider range when datasets are added or deleted
        # Priority 0 ensures this runs before normal observers but after bookmark restoration
        observe(
            {
                watch("refresh_datasets")

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
            priority = 0
        )

        # Show/hide sections based on active page
        # Also sync with session$userData$selected_dataset_id when navigating to dataset page
        observeEvent(active_page(), {
            page <- active_page()
            if (purrr::is_empty(page)) {
                return()
            }

            if (page == "home") {
                shinyjs::show("home_filter_section")
                shinyjs::hide("dataset_params_section")
            } else if (page == "dataset") {
                shinyjs::hide("home_filter_section")
                shinyjs::show("dataset_params_section")
                # Sync with externally set dataset ID (e.g., from home page row click)
                external_id <- session$userData$selected_dataset_id
                if (!purrr::is_empty(external_id) && external_id != values$selected_dataset_id) {
                    values$selected_dataset_id <- external_id
                    updateSelectInput(session, "selected_dataset", selected = as.character(external_id))
                }
            } else {
                shinyjs::hide("home_filter_section")
                shinyjs::hide("dataset_params_section")
            }
        })

        return(values)
    })
}
