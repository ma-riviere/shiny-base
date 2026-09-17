# Sidebar server module
# Manages the dataset selection dropdown and home filters.
# The model module (300_model) handles the saved-model picker shown in this sidebar.
# Section visibility is handled by conditionalPanel in sidebar_ui.R (browser-side).
#
# @param selected_dataset_id reactiveVal for currently selected dataset ID (read/write)
sidebar_server <- function(id, selected_dataset_id) {
    moduleServer(id, function(input, output, session) {
        # Hide admin users sidebar section for users without auth0 admin access
        if (!can("view:admin:auth0")) {
            shinyjs::hide("admin_users_section")
        }

        values <- reactiveValues(
            user_datasets = NULL,
            row_count_filter = c(0, 100000),
            age_filter = c(Sys.Date() - 365, Sys.Date()),
            prev_max_rows = NULL, # Track previous max to detect actual changes
            preview_rows = c(1L, 10L), # Explore data preview: c(from, to) row range
            # Dataset the preview slider was last set for (lags selected_dataset_id by one run):
            # tells a dataset switch (reset) from a refresh of the same dataset (keep the range)
            prev_preview_dataset_id = NULL
        )

        # ------ SHARED STATE SYNC ---------------------------------------------

        # Reflect selections made elsewhere, e.g. a dataset row clicked on Home.
        observeEvent(
            selected_dataset_id(),
            {
                req(selected_dataset_id())
                updateSelectInput(
                    session,
                    "selected_dataset",
                    selected = as.character(selected_dataset_id())
                )
            },
            ignoreNULL = TRUE,
            ignoreInit = TRUE,
            label = "sidebar_sync_shared_to_dropdown"
        )

        # Share dropdown changes with the pages that use the selected dataset.
        observeEvent(
            input$selected_dataset,
            {
                if (
                    purrr::is_empty(input$selected_dataset) ||
                        !nzchar(input$selected_dataset)
                ) {
                    selected_dataset_id(NULL)
                } else {
                    selected_dataset_id(as.integer(input$selected_dataset))
                }
            },
            label = "sidebar_sync_dropdown_to_shared"
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
                    selected_dataset_id() %||% get_restored_input("selected_dataset")
                )

                if (purrr::is_empty(datasets) || nrow(datasets) == 0) {
                    updateSelectInput(
                        session,
                        "selected_dataset",
                        choices = c("No datasets" = ""),
                        selected = ""
                    )
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
                    selected_dataset_id(as.integer(new_selected))
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

                    # Reset on first load or when the largest dataset changes.
                    # Moving the slider must preserve the user's chosen range.
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

        # ------ PREVIEW ROWS (explore) ----------------------------------------

        observeEvent(
            input$preview_rows,
            {
                values$preview_rows <- as.integer(input$preview_rows)
            },
            label = "sidebar_preview_rows"
        )

        # The slider's max follows the selected dataset: min(row count, preview cap).
        # The range resets to 1-10 on a dataset switch, keeps its value when the same
        # dataset is refreshed (rename), and comes from the bookmark on restore when the
        # restored dataset is the one selected. Row counts come from the dataset list
        # already loaded for the dropdown; explore re-validates against the loaded data.
        observeEvent(
            list(selected_dataset_id(), values$user_datasets),
            {
                dataset_id <- selected_dataset_id()
                datasets <- values$user_datasets
                max_rows <- getOption("preview_max_rows", 100L)

                n_rows <- 0L
                if (!purrr::is_empty(dataset_id) && !purrr::is_empty(datasets)) {
                    n_rows <- datasets$row_count[match(dataset_id, datasets$id)]
                }
                n_rows <- min(max(n_rows, 0L, na.rm = TRUE), max_rows)

                same_dataset <- identical(values$prev_preview_dataset_id, dataset_id)
                # First dataset of the session: take the bookmarked range if it was saved for this dataset
                restored <- NULL
                if (
                    purrr::is_empty(values$prev_preview_dataset_id) &&
                        identical(as.integer(get_restored_input("selected_dataset")), dataset_id)
                ) {
                    restored <- get_restored_input("preview_rows")
                }
                range <- if (same_dataset) input$preview_rows else restored %||% c(1L, 10L)
                range <- pmin(pmax(as.integer(range), 1L), max(n_rows, 1L))

                # A range slider needs max > min; a dataset with 0 or 1 row has nothing to slide over
                updateSliderInput(session, "preview_rows", max = max(n_rows, 2L), value = range)
                shinyjs::toggleState("preview_rows", condition = n_rows > 1L)
                values$preview_rows <- range
                values$prev_preview_dataset_id <- dataset_id
            },
            ignoreNULL = FALSE,
            label = "sidebar_preview_bounds"
        )

        # Note: Section visibility is handled by conditionalPanel in sidebar_ui.R
        # based on input.nav value (runs in browser, no server round-trip needed)

        return(values)
    })
}
