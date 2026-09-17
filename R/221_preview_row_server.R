# Row server: created once per row by 220_data_preview_server.R and kept while its dataset is selected,
# whether or not the row is in the displayed range ("initialize once, gate while hidden").
#
# While the row is out of range, its <tr> is not in the DOM: Shiny suspends the row's output, and the
# checkbox observer has nothing to react to. Its state (input$selected) stays in the session.
#
# @param row_index Row of the dataset this module shows (1-based, stable within one dataset).
# @param data Reactive: the dataset (data.frame).
# @param visible_rows Reactive: row indices currently displayed by the parent.
preview_row_server <- function(id, row_index, data, visible_rows) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Selections are transient: a restored checkbox would re-select the row at the next start
        setBookmarkExclude("selected")

        visible <- reactive(row_index %in% visible_rows(), label = "preview_row_visible")

        # ------ REACTIVE ------------------------------------------------------

        # Pull side: only this row's output reads it, and Shiny suspends that output while the row is not in the
        # DOM. The req() is a guard for any other consumer, not the gate.
        record <- reactive(label = "preview_row_record", {
            req(visible())
            data()[row_index, , drop = FALSE]
        })

        # ------ OUTPUT --------------------------------------------------------

        output$row <- renderUI({
            record <- record()
            tagList(
                # The checkbox element is rebuilt every time the row re-enters the range, and a rebuilt input
                # sends its constructor value. input$selected keeps its last value while the element is gone
                # (only session$destroy() drops it), so the rebuilt checkbox is seeded from it.
                # isolate(): a click must not re-render the row.
                tags$td(
                    class = "preview-select",
                    checkboxInput(
                        ns("selected"),
                        label = tags$span(class = "visually-hidden", tr("Select row")),
                        value = isTRUE(isolate(input$selected))
                    )
                ),
                tags$th(scope = "row", rownames(record)),
                lapply(record, \(value) tags$td(format(value, scientific = FALSE, trim = TRUE)))
            )
        })

        return(list(selected = reactive(isTRUE(input$selected), label = "preview_row_selected")))
    })
}
