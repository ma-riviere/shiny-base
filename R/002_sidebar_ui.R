sidebar_ui <- function(id) {
    ns <- NS(id)
    bslib::sidebar(
        id = ns("sidebar"),
        width = 280,
        open = "desktop",
        # Home page filter section
        div(
            id = ns("home_filter_section"),
            h6(
                class = "text-uppercase text-muted fw-semibold mb-3 i18n",
                `data-key` = "Filters",
                tr("Filters")
            ),
            sliderInput(
                ns("row_count_filter"),
                label = tags$span(
                    class = "i18n",
                    `data-key` = "Filter by row count",
                    tr("Filter by row count")
                ),
                min = 0,
                max = 100000,
                value = c(0, 100000),
                step = 100,
                width = "100%"
            )
        ),
        # Dataset page parameters section
        div(
            id = ns("dataset_params_section"),
            h6(
                class = "text-uppercase text-muted fw-semibold mb-3 i18n",
                `data-key` = "Dataset",
                tr("Dataset")
            ),
            selectInput(
                ns("selected_dataset"),
                label = tags$span(
                    class = "i18n",
                    `data-key` = "Select Dataset",
                    tr("Select Dataset")
                ),
                choices = c("No datasets" = ""),
                selected = ""
            )
        ),
        # Footer with bookmark button
        div(
            class = "mt-auto pt-3 border-top",
            bookmarkButton(
                label = tr("Save State"),
                class = "btn btn-outline-secondary btn-sm w-100"
            )
        )
    )
}
