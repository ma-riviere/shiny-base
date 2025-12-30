model_ui <- function(id) {
    ns <- NS(id)
    div(
        id = ns("main"),
        class = "page page-model",
        div(
            class = "page-header",
            h1(class = "i18n", `data-key` = "Model", tr("Model")),
            p(
                class = "lead i18n",
                `data-key` = "Fit linear models to your data",
                tr("Fit linear models to your data")
            )
        ),
        # ----- MODEL INPUT SECTION --------------------------------------------
        div(
            class = "content-section mb-4",
            div(
                class = "card",
                div(
                    class = "card-body",
                    h5(
                        class = "card-title i18n",
                        `data-key` = "Model Equation",
                        tr("Model Equation")
                    ),
                    div(
                        class = "d-flex gap-2 align-items-start",
                        div(
                            class = "flex-grow-1",
                            textInput(
                                ns("equation"),
                                label = NULL,
                                placeholder = "y ~ x1 + x2",
                                width = "100%"
                            )
                        ),
                        bslib::input_task_button(
                            ns("fit_btn"),
                            label = tagList(
                                bsicons::bs_icon("play-fill"),
                                tags$span(class = "i18n", `data-key` = "Fit", tr("Fit"))
                            ),
                            class = "btn-primary"
                        ),
                        actionButton(
                            ns("save_btn"),
                            label = tagList(
                                bsicons::bs_icon("floppy"),
                                tags$span(class = "i18n", `data-key` = "Save", tr("Save"))
                            ),
                            class = "btn-outline-secondary",
                            disabled = "disabled"
                        ),
                        actionButton(
                            ns("delete_btn"),
                            label = tagList(
                                bsicons::bs_icon("trash"),
                                tags$span(class = "i18n", `data-key` = "Delete", tr("Delete"))
                            ),
                            class = "btn-outline-danger",
                            disabled = "disabled"
                        )
                    ),
                    tags$small(
                        class = "text-muted i18n",
                        `data-key` = "Enter an R formula (e.g., y ~ x1 + x2, y ~ poly(x, 2))",
                        tr("Enter an R formula (e.g., y ~ x1 + x2, y ~ poly(x, 2))")
                    ),
                    uiOutput(ns("available_vars"))
                )
            )
        ),
        # ----- MODEL RESULTS SECTION ------------------------------------------
        shinyjs::hidden(
            div(
                id = ns("results_section"),
                class = "content-section",
                div(
                    class = "card",
                    div(
                        class = "card-body",
                        h5(
                            class = "card-title i18n",
                            `data-key` = "Model Summary",
                            tr("Model Summary")
                        ),
                        # Metrics row
                        div(
                            class = "row mb-3",
                            div(
                                class = "col-md-4",
                                div(
                                    class = "metric-card p-3 border rounded",
                                    tags$small(class = "text-muted", "R-squared"),
                                    div(class = "h4 mb-0", textOutput(ns("r_squared"), inline = TRUE))
                                )
                            ),
                            div(
                                class = "col-md-4",
                                div(
                                    class = "metric-card p-3 border rounded",
                                    tags$small(class = "text-muted", "RMSE"),
                                    div(class = "h4 mb-0", textOutput(ns("rmse"), inline = TRUE))
                                )
                            ),
                            div(
                                class = "col-md-4",
                                div(
                                    class = "metric-card p-3 border rounded",
                                    tags$small(class = "text-muted", "AIC"),
                                    div(class = "h4 mb-0", textOutput(ns("aic"), inline = TRUE))
                                )
                            )
                        ),
                        # Summary output
                        verbatimTextOutput(ns("summary"))
                    )
                )
            )
        ),
        # ----- EMPTY STATE ----------------------------------------------------
        shinyjs::hidden(
            div(
                id = ns("empty_state"),
                class = "empty-state-overlay",
                div(
                    class = "empty-state",
                    bsicons::bs_icon("graph-up", size = "3rem"),
                    p(
                        class = "i18n",
                        `data-key` = "No dataset selected",
                        tr("No dataset selected")
                    ),
                    p(
                        tags$small(
                            class = "text-muted i18n",
                            `data-key` = "Select a dataset from the sidebar to start modeling",
                            tr("Select a dataset from the sidebar to start modeling")
                        )
                    )
                )
            )
        )
    )
}
