dataset_server <- function(id, selected_dataset_id = reactive(NULL), nav_select_callback = NULL) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        values <- reactiveValues(
            dataset = NULL,
            data = NULL
        )

        # ------ REACTIVE ------------------------------------------------------

        # Load dataset when selection changes (from sidebar dropdown)
        observe({
            # Get dataset_id from reactive (which is bound to sidebar selection)
            dataset_id <- selected_dataset_id()

            if (purrr::is_empty(dataset_id)) {
                values$dataset <- NULL
                values$data <- NULL
                return()
            }

            # Fetch dataset from DB
            dataset_row <- db_get_dataset(pool, dataset_id)
            if (purrr::is_empty(dataset_row)) {
                values$dataset <- NULL
                values$data <- NULL
                return()
            }

            values$dataset <- dataset_row

            # Parse JSON data to data frame
            tryCatch(
                {
                    values$data <- db_parse_dataset_data(dataset_row$data)
                },
                error = \(e) {
                    values$data <- NULL
                    shinyWidgets::show_toast(
                        title = paste(tr("Error parsing dataset:"), e$message),
                        type = "error",
                        timer = 5000,
                        position = "bottom-end"
                    )
                }
            )
        })

        has_data <- reactive({
            !purrr::is_empty(values$data)
        })

        # ------ OUTPUT --------------------------------------------------------

        output$dataset_description <- renderUI({
            if (!has_data()) {
                return(
                    tags$span(
                        class = "i18n",
                        `data-key` = "Select a dataset to explore",
                        tr("Select a dataset to explore")
                    )
                )
            }
            tags$span(
                class = "i18n",
                `data-key` = "Explore your uploaded dataset",
                tr("Explore your uploaded dataset")
            )
        })

        output$dataset_name <- renderText({
            if (!has_data()) {
                return("-")
            }
            purrr::pluck(values$dataset, "name") %||% "-"
        })

        output$row_count <- renderText({
            if (!has_data()) {
                return("0")
            }
            format(nrow(values$data), big.mark = ",")
        })

        output$col_count <- renderText({
            if (!has_data()) {
                return("0")
            }
            ncol(values$data)
        })

        output$data_preview <- DT::renderDataTable({
            req(has_data())
            DT::datatable(
                values$data,
                options = list(
                    pageLength = 10,
                    scrollX = TRUE,
                    dom = "frtip"
                ),
                class = "display compact",
                rownames = FALSE
            )
        })

        output$data_summary <- renderPrint({
            req(has_data())
            summary(values$data)
        })

        output$empty_state <- renderUI({
            if (has_data()) {
                return(NULL)
            }
            div(
                class = "empty-state-overlay",
                div(
                    class = "empty-state",
                    bsicons::bs_icon("table", size = "3rem"),
                    p(
                        class = "i18n",
                        `data-key` = "No dataset selected",
                        tr("No dataset selected")
                    ),
                    p(
                        tags$small(
                            class = "text-muted i18n",
                            `data-key` = "Go to Home and click on a dataset to view it here",
                            tr("Go to Home and click on a dataset to view it here")
                        )
                    ),
                    actionButton(
                        ns("go_home"),
                        tagList(
                            bsicons::bs_icon("house"),
                            tags$span(class = "i18n", `data-key` = "Go to Home", tr("Go to Home"))
                        ),
                        class = "btn-primary"
                    )
                )
            )
        })

        # Navigate to home page
        observeEvent(input$go_home, {
            if (!is.null(nav_select_callback)) {
                nav_select_callback("home")
            }
        })
    })
}
