# Home page server module
# Displays dataset list with filtering and handles dataset row clicks.
#
# @param selected_dataset_id reactiveVal for selected dataset ID (write on row click)
# @param on_edit Callback opening the rename modal (forwarded to dataset_actions)
home_server <- function(
    id,
    row_count_filter = reactive(c(0, 100000)),
    age_filter = reactive(c(Sys.Date() - 365, Sys.Date())),
    nav_select_callback = NULL,
    selected_dataset_id,
    on_edit
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(datasets = NULL)

        # ------ REACTIVE ------------------------------------------------------

        # Fetch datasets on init and when refresh is triggered
        observeEvent(
            watch("refresh_datasets"),
            {
                user_id <- purrr::pluck(session$userData$user, "id")
                req(user_id)
                values$datasets <- db_get_user_datasets(user_id)
            },
            ignoreInit = FALSE,
            label = "home_fetch_datasets"
        )

        # Filter datasets based on row count slider and date range from sidebar
        filtered_datasets <- reactive(label = "home_filtered_datasets", {
            req(values$datasets)
            row_filter_range <- row_count_filter()
            date_filter_range <- age_filter()

            datasets <- values$datasets

            # Apply row count filter
            if (!purrr::is_empty(row_filter_range) && length(row_filter_range) == 2) {
                datasets <- datasets[
                    datasets$row_count >= row_filter_range[1] &
                        datasets$row_count <= row_filter_range[2],
                ]
            }

            # Apply age filter (based on created_at)
            if (!purrr::is_empty(date_filter_range) && length(date_filter_range) == 2) {
                datasets$created_date <- as.Date(datasets$created_at)
                datasets <- datasets[
                    datasets$created_date >= date_filter_range[1] &
                        datasets$created_date <= date_filter_range[2],
                ]
                datasets$created_date <- NULL
            }

            return(datasets)
        })

        # Open upload modal
        observeEvent(
            input$open_upload,
            trigger("show_upload_modal"),
            label = "home_open_upload"
        )

        # ------ MODULE --------------------------------------------------------

        # Shared row-action handlers (edit / download / delete): one instance
        # covering ALL rows ("one observer for all rows" pattern)
        dataset_actions_server(
            "actions",
            datasets = reactive(values$datasets),
            on_edit = on_edit
        )

        # Row click (single observer for all rows): select the dataset and
        # navigate. Event-priority input, so re-clicking the same row re-fires.
        observeEvent(input$dataset_click, label = "home_dataset_click", {
            row_idx <- match(as.character(input$dataset_click), as.character(values$datasets$id))
            req(!is.na(row_idx))
            selected_dataset_id(values$datasets$id[row_idx])
            if (!is.null(nav_select_callback)) {
                nav_select_callback("explore")
            }
        })

        # ------ OUTPUT --------------------------------------------------------

        output$dataset_count <- renderText(nrow(values$datasets) %||% 0)

        output$dataset_list <- renderUI({
            datasets <- filtered_datasets()

            if (purrr::is_empty(datasets) || nrow(datasets) == 0) {
                return(
                    div(
                        class = "empty-state",
                        bsicons::bs_icon("folder2-open", size = "3rem"),
                        p(
                            class = "i18n",
                            `data-key` = "No datasets match the current filter",
                            tr("No datasets match the current filter")
                        )
                    )
                )
            }

            # Render each dataset row straight from data (no per-row module);
            # actions target the shared dataset_actions instance
            can_delete <- can("delete:dataset")
            actions_ns <- NS(ns("actions"))
            dataset_rows <- purrr::map(
                seq_len(nrow(datasets)),
                \(i) {
                    dataset_row_ui(
                        actions_ns,
                        datasets[i, ],
                        select_input_id = ns("dataset_click"),
                        can_delete = can_delete
                    )
                }
            )
            tagList(dataset_rows)
        })
    })
}
