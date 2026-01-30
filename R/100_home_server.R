# Home page server module
# Displays dataset list with filtering and handles dataset row clicks.
#
# @param selected_dataset_id reactiveVal for selected dataset ID (write on row click)
home_server <- function(
    id,
    row_count_filter = reactive(c(0, 100000)),
    age_filter = reactive(c(Sys.Date() - 365, Sys.Date())),
    nav_select_callback = NULL,
    selected_dataset_id
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(datasets = NULL)

        # Cache for initialized row module IDs (Initialize Once pattern)
        loaded_row_ids <- reactiveVal(character(0))

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

        # Initialize row module servers ONCE per new dataset ID
        observeEvent(values$datasets, label = "home_init_row_modules", {
            req(values$datasets)
            current_ids <- paste0("row_", values$datasets$id)
            new_ids <- setdiff(current_ids, loaded_row_ids())

            # Use lapply instead of for loop to avoid lazy evaluation trap.
            # for loops reuse the same environment - by the time reactives execute,
            # they see the LAST value of the loop variable. lapply creates a new
            # environment per iteration, freezing each value.
            lapply(new_ids, \(rid) {
                numeric_id <- as.integer(sub("row_", "", rid))
                dataset_row_server(
                    rid,
                    all_datasets = reactive(values$datasets),
                    row_id = reactive({
                        numeric_id
                    }),
                    on_click = \(dataset_id) {
                        selected_dataset_id(dataset_id)
                        if (!is.null(nav_select_callback)) {
                            nav_select_callback("explore")
                        }
                    }
                )
            })
            loaded_row_ids(union(loaded_row_ids(), new_ids))
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

            # Render each dataset row using module UI
            can_delete <- can("delete:dataset")
            dataset_rows <- purrr::map(
                datasets$id,
                \(id) {
                    dataset_row_ui(
                        ns(paste0("row_", id)),
                        clickable = TRUE,
                        can_delete = can_delete
                    )
                }
            )
            tagList(dataset_rows)
        })
    })
}
