# One row of the Explore data preview (child of 220_data_preview).
# The UI is a placeholder <tr> that the row's own output fills: the parent only lists which rows exist.

preview_row_ui <- function(id) {
    ns <- NS(id)
    # A <div> placeholder inside a <table> is moved out of the table by the HTML parser: the output IS the <tr>
    return(uiOutput(ns("row"), container = tags$tr))
}
