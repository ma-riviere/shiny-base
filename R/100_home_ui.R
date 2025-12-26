home_ui <- function(id) {
    ns <- NS(id)
    div(
        id = ns("main"),
        class = "page page-home",
        div(
            class = "page-header",
            h1(class = "i18n", `data-key` = "Home", tr("Home")),
            p(
                class = "lead i18n",
                `data-key` = "Your uploaded datasets.",
                tr("Your uploaded datasets.")
            )
        ),
        # ------ SUMMARY CARDS -------------------------------------------------
        div(
            class = "content-grid",
            div(
                class = "card stat-card",
                div(class = "stat-icon", bsicons::bs_icon("database")),
                div(
                    class = "stat-content",
                    span(class = "stat-value", textOutput(ns("dataset_count"), inline = TRUE)),
                    span(
                        class = "stat-label i18n",
                        `data-key` = "Datasets",
                        tr("Datasets")
                    )
                )
            )
        ),
        # ------ DATASET LIST --------------------------------------------------
        div(
            class = "content-section",
            div(
                class = "card datasets-card",
                div(
                    class = "card-header",
                    h3(class = "i18n", `data-key` = "Your Datasets", tr("Your Datasets")),
                    actionButton(
                        ns("open_upload"),
                        tagList(
                            bsicons::bs_icon("upload"),
                            tags$span(class = "i18n", `data-key` = "Upload Dataset", tr("Upload Dataset"))
                        ),
                        class = "btn-primary"
                    )
                ),
                div(
                    class = "card-body",
                    uiOutput(ns("dataset_list"))
                )
            )
        )
    )
}
