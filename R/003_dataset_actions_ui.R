# Render dataset rows without creating a server module for each row.
# Each action sends the dataset ID to the page's shared handler (dataset_actions_server()).
# input_button() and www/js/app.js connect the buttons to those inputs, as in the model picker.

# Downloads use one hidden link per page. Row buttons choose the dataset, then click this link.
dataset_actions_ui <- function(id) {
    ns <- NS(id)
    return(shinyjs::hidden(downloadLink(ns("download_file"), label = NULL)))
}

# Render one dataset row (name, age, size + action buttons).
#
# @param actions_ns Namespace function of the page's dataset_actions instance, i.e. NS(ns("actions"))
#   in the host: actions_ns("edit") gives "home-actions-edit", an input of that child module. A row
#   is not a module and has no namespace of its own: its buttons point at the shared handler's inputs.
# @param dataset One-row data.frame with id, name, created_at, row_count, col_count.
# @param select_input_id Input set when the row body (name, age, size) is clicked, e.g. Home's
#   ns("dataset_click"). It belongs to the HOST page, not to dataset_actions: the host decides what a
#   selection does (Home selects the dataset and navigates to Explore). NULL = plain, non-clickable
#   row (Explore's summary row: that dataset is already the selected one).
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
    # Clickable flavour: a native <button> (focus, Enter/Space for free). event = TRUE although this
    # is a selection: re-clicking the current dataset must still navigate, and a stable value would
    # be deduplicated. Hence the host excludes this input from bookmarks; the selection itself
    # persists through the sidebar dropdown.
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
