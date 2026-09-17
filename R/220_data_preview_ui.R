# Explore data preview: a plain HTML table whose rows are modules (221_preview_row),
# shown or hidden by the sidebar's row-range slider.
#
# Illustrates "initialize once, gate while hidden": a row's server is created the first
# time the row enters the range and kept while the dataset stays selected. The parent's
# renderUI() only lists the rows in range; each row's own output fills its <tr>.
# The rows' selection (checkbox) survives leaving and re-entering the range.

data_preview_ui <- function(id) {
    ns <- NS(id)
    return(tagList(
        p(class = "text-muted small preview-caption", textOutput(ns("caption"), inline = TRUE)),
        div(class = "table-container", uiOutput(ns("table")))
    ))
}
