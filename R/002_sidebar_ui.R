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
                ) |>
                    tagAppendAttributes(`data-shiny-input-rate-policy` = '{"policy": "debounce", "delay": 300}'),
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
        # ------ MODEL PARAMETERS SECTION -----------------------------------------
        # Visible only on model page
        conditionalPanel(
            condition = "input.nav === 'model'",
            div(
                id = ns("model_params_section"),
                h6(
                    class = "text-uppercase text-muted fw-semibold mb-3 i18n",
                    `data-key` = "Saved Models",
                    tr("Saved Models")
                ),
                selectInput(
                    ns("selected_model"),
                    label = tags$span(
                        class = "i18n",
                        `data-key` = "Load Model",
                        tr("Load Model")
                    ),
                    choices = c("No models" = ""),
                    selected = ""
                )
            )
        ),
        # ------ ADMIN USERS SECTION ----------------------------------------------
        # Visible only on admin page, users sub-tab
        conditionalPanel(
            condition = "input.nav === 'admin' && input['admin-admin_tabs'] === 'users'",
            div(
                id = ns("admin_users_section"),
                h6(
                    class = "text-uppercase text-muted fw-semibold mb-3 i18n",
                    `data-key` = "View",
                    tr("View")
                ),
                radioButtons(
                    ns("admin_users_view"),
                    label = NULL,
                    choiceNames = list(
                        tags$span(class = "i18n", `data-key` = "Currently Connected", tr("Currently Connected")),
                        tags$span(class = "i18n", `data-key` = "All Users", tr("All Users"))
                    ),
                    choiceValues = c("connected", "all"),
                    selected = "connected"
                ),
                checkboxInput(
                    ns("admin_show_only_recent"),
                    label = tags$span(
                        class = "i18n",
                        `data-key` = "Show only most recent",
                        tr("Show only most recent")
                    ),
                    value = FALSE
                )
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
