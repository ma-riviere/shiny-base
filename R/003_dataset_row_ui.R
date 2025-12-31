# Dataset row UI component
# Renders a single dataset row with name, date, size, and action buttons
dataset_row_ui <- function(id, clickable = TRUE) {
    ns <- NS(id)

    # ------ MAIN CONTENT ------------------------------------------------------
    # Info displayed on the dataset (Name, Age, Size)
    # This will be inside the actionLink if clickable
    main_content <- tagList(
        # Name column
        div(
            class = "dataset-col dataset-col-name",
            span(class = "dataset-name", textOutput(ns("name"), inline = TRUE))
        ),

        # Age column
        div(
            class = "dataset-col dataset-col-age",
            bsicons::bs_icon("calendar-plus", size = "14px"),
            span(textOutput(ns("created_at"), inline = TRUE))
        ),

        # Size column
        div(
            class = "dataset-col dataset-col-size",
            bsicons::bs_icon("table", size = "14px"),
            span(textOutput(ns("size"), inline = TRUE))
        )
    )

    # ------ ACTIONS CONTENT ---------------------------------------------------
    # Buttons (edit, download, delete)
    # This acts as the second column in the outer grid
    actions_content <- div(
        class = "dataset-col dataset-col-actions",
        actionButton(
            ns("edit"),
            label = NULL,
            icon = icon("pencil"),
            class = "btn btn-sm btn-outline-secondary btn-action-dataset",
            title = "Rename dataset"
        ),
        tags$a(
            id = ns("download"),
            class = "btn btn-sm btn-outline-primary btn-action-dataset shiny-download-link",
            href = "",
            target = "_blank",
            download = NA,
            icon("download"),
            onclick = "event.stopPropagation();"
        ),
        shinyjs::hidden(
            actionButton(
                ns("delete"),
                label = NULL,
                icon = icon("trash"),
                class = "btn btn-sm btn-outline-danger btn-action-dataset",
                title = "Delete dataset"
            )
        )
    )

    # ------ UI ----------------------------------------------------------------
    if (clickable) {
        # Clickable:
        # Outer div (dataset-row) holds:
        #   1. actionLink (dataset-row-link) -> contains main_content
        #   2. actions_content
        div(
            class = "dataset-row",
            actionLink(
                ns("row_click"),
                label = main_content,
                class = "dataset-row-link clickable"
            ),
            actions_content
        )
    } else {
        # Non-clickable:
        # Outer div (dataset-row) holds:
        #   1. div (dataset-row-link) -> contains main_content
        #   2. actions_content
        div(
            class = "dataset-row",
            div(
                class = "dataset-row-link",
                main_content
            ),
            actions_content
        )
    }
}
