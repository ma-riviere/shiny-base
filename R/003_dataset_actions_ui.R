# Dataset row rendering + shared action UI ("one observer for all rows" pattern)
#
# dataset_row_ui() renders a row straight from data (no per-row module): every
# button targets the SAME input of the hosting page's dataset_actions module
# instance (see input_button() in helpers_inputs.R and the delegated click
# handler in www/js/app.js), carrying the dataset id. Same architecture as the
# saved-models picker.

# Hidden download anchor backing the single downloadHandler of
# dataset_actions_server() (per-row download buttons proxy through it).
dataset_actions_ui <- function(id) {
    ns <- NS(id)
    return(shinyjs::hidden(downloadLink(ns("download_file"), label = NULL)))
}

# Render one dataset row (name, age, size + action buttons).
#
# @param actions_ns Namespace function of the hosting page's dataset_actions
#   instance (e.g. NS(ns("actions"))): buttons set its edit/download/delete
#   event inputs.
# @param dataset One-row data.frame with id, name, created_at, row_count, col_count.
# @param select_input_id Namespaced event input id set when the row body is
#   clicked (NULL = row not clickable).
# @param can_delete Include the delete button (RBAC-checked by the caller).
dataset_row_ui <- function(actions_ns, dataset, select_input_id = NULL, can_delete = FALSE) {
    # ------ MAIN CONTENT ------------------------------------------------------
    # Info displayed on the dataset (Name, Age, Size). Columns are <span>s: the
    # clickable flavour wraps them in a native <button>, which only allows
    # phrasing content (and provides Enter/Space activation + focus for free).
    main_content <- tagList(
        # Name column
        span(
            class = "dataset-col dataset-col-name",
            span(class = "dataset-name", dataset$name)
        ),

        # Age column
        span(
            class = "dataset-col dataset-col-age",
            bsicons::bs_icon("calendar-plus", size = "14px"),
            span(format(as.Date(dataset$created_at), "%Y-%m-%d"))
        ),

        # Size column
        span(
            class = "dataset-col dataset-col-size",
            bsicons::bs_icon("table", size = "14px"),
            span(paste0(
                format(dataset$row_count, big.mark = ","),
                " rows × ",
                dataset$col_count,
                " cols"
            ))
        )
    )

    # ------ ACTIONS CONTENT ---------------------------------------------------
    # Buttons (edit, download, delete): event inputs on the dataset_actions module
    actions_content <- div(
        class = "dataset-col dataset-col-actions",
        input_button(
            actions_ns("edit"),
            dataset$id,
            event = TRUE,
            bsicons::bs_icon("pencil"),
            class = "btn btn-sm btn-outline-secondary btn-action-dataset",
            title = tr("Rename dataset")
        ),
        input_button(
            actions_ns("download"),
            dataset$id,
            event = TRUE,
            bsicons::bs_icon("download"),
            class = "btn btn-sm btn-outline-primary btn-action-dataset",
            title = tr("Download dataset")
        ),
        if (can_delete) {
            input_button(
                actions_ns("delete"),
                dataset$id,
                event = TRUE,
                bsicons::bs_icon("trash"),
                class = "btn btn-sm btn-outline-danger btn-action-dataset",
                title = tr("Delete dataset")
            )
        }
    )

    # ------ UI ----------------------------------------------------------------
    row_body <- if (!is.null(select_input_id)) {
        input_button(
            select_input_id,
            dataset$id,
            event = TRUE,
            main_content,
            class = "dataset-row-link clickable"
        )
    } else {
        div(class = "dataset-row-link", main_content)
    }

    return(div(class = "dataset-row", row_body, actions_content))
}
