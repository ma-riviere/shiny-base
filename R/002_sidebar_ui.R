sidebar_ui <- function(id) {
    ns <- NS(id)
    bslib::sidebar(
        id = ns("sidebar"),
        width = 280,
        # Collapse by default on mobile, open on desktop
        open = list(desktop = "open", mobile = "closed"),
        # ------ HOME FILTER SECTION -------------------------------------------
        # Visible only on home page
        conditionalPanel(
            condition = "input.nav === 'home'",
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
                ),
                dateRangeInput(
                    ns("age_filter"),
                    label = tags$span(
                        class = "i18n",
                        `data-key` = "Filter by date",
                        tr("Filter by date")
                    ),
                    start = Sys.Date() - 365,
                    end = Sys.Date(),
                    format = "yyyy-mm-dd",
                    weekstart = 1,
                    width = "100%"
                )
            )
        ),
        # ------ DATASET PARAMETERS SECTION ------------------------------------
        # Visible on dataset and model pages
        conditionalPanel(
            condition = "input.nav === 'explore' || input.nav === 'model'",
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
            )
        ),
        # ------ PREVIEW SECTION -----------------------------------------------
        # Visible only on the explore page: which rows of the selected dataset the
        # data preview shows. The static max is the preview cap, so a restored
        # (bookmarked) range is always representable when the slider is built;
        # the server then lowers the max to the dataset's row count.
        conditionalPanel(
            condition = "input.nav === 'explore'",
            div(
                id = ns("preview_section"),
                h6(
                    class = "text-uppercase text-muted fw-semibold mb-3 i18n",
                    `data-key` = "Preview",
                    tr("Preview")
                ),
                sliderInput(
                    ns("preview_rows"),
                    label = tags$span(
                        class = "i18n",
                        `data-key` = "Rows to show",
                        tr("Rows to show")
                    ),
                    min = 1,
                    max = getOption("preview_max_rows", 100L),
                    value = c(1, 10),
                    step = 1,
                    width = "100%"
                )
            )
        ),
        # ------ MODEL PARAMETERS SECTION --------------------------------------
        # Visible only on model page. The saved-models picker is rendered by the
        # model module, so we host its output here via the model namespace.
        conditionalPanel(
            condition = "input.nav === 'model'",
            div(
                id = ns("model_params_section"),
                h6(
                    class = "text-uppercase text-muted fw-semibold mb-3 i18n",
                    `data-key` = "Saved Models",
                    tr("Saved Models")
                ),
                uiOutput(NS("model")("saved_models"))
            )
        ),
        # ------ FOOTER --------------------------------------------------------
        div(
            class = "mt-auto pt-3 border-top",
            bookmarkButton(
                label = tr("Save State"),
                class = "btn btn-outline-secondary btn-sm w-100"
            )
        )
    )
}
