sidebar_server <- function(
    id,
    active_page = reactive(NULL)
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns
        values <- reactiveValues(
            selected_dataset_id = NULL,
            user_datasets = NULL,
            row_count_filter = c(0, 100000)
        )

        # ------ REACTIVE ------------------------------------------------------

        # Load user datasets for dropdown
        observe({
            auth_info <- session$userData$auth0_info
            if (purrr::is_empty(auth_info)) {
                return()
            }

            auth0_sub <- purrr::pluck(auth_info, "sub")
            if (purrr::is_empty(auth0_sub)) {
                return()
            }

            # Get user and their datasets
            user <- db_get_or_create_user(pool, auth0_sub)
            user_id <- purrr::pluck(user, "id")
            datasets <- db_get_user_datasets(pool, user_id)
            values$user_datasets <- datasets

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
                updateSelectInput(
                    session,
                    "selected_dataset",
                    choices = choices,
                    selected = datasets$id[1]
                )
            }
        })

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

        # Update slider range when datasets change
        # Priority 0 ensures this runs before normal observers but after bookmark restoration
        observe(
            {
                req(values$user_datasets)
                if (nrow(values$user_datasets) > 0) {
                    max_rows <- max(values$user_datasets$row_count, na.rm = TRUE)
                    min_rows <- min(values$user_datasets$row_count, na.rm = TRUE)

                    # Only update value if it's still at the default (meaning not bookmarked)
                    # or if the current value is outside the new range
                    current_value <- input$row_count_filter
                    should_update_value <- purrr::is_empty(current_value) ||
                        identical(current_value, c(0L, 100000L)) ||
                        current_value[1] < min_rows ||
                        current_value[2] > max_rows

                    if (should_update_value) {
                        updateSliderInput(
                            session,
                            "row_count_filter",
                            min = min_rows,
                            max = max_rows,
                            value = c(min_rows, max_rows)
                        )
                    } else {
                        # Just update the range, keep the current value
                        updateSliderInput(
                            session,
                            "row_count_filter",
                            min = min_rows,
                            max = max_rows
                        )
                    }
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
