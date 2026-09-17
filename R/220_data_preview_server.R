# Data preview server: parent of the row modules (see 220_data_preview_ui.R).
#
# @param data Reactive: the selected dataset (data.frame), NULL when none.
# @param dataset_id Reactive: id of the selected dataset. Row servers live as long as it stays selected.
# @param preview_rows Reactive: c(from, to), the row range from the sidebar slider.
# @param max_rows Only the first max_rows rows can be previewed: the slider stops there, so at most that many
#   row servers exist per dataset (they are retained while the dataset is selected, whatever the range shows).
data_preview_server <- function(
    id,
    data,
    dataset_id,
    preview_rows,
    max_rows = getOption("preview_max_rows", 100L)
) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Row servers of the current dataset: row index (as name) -> list(module_id, selected reactive)
        rows <- reactiveValues(dataset_id = NULL, modules = list())

        # ------ REACTIVE ------------------------------------------------------

        # Rows in range, validated against the loaded data (the slider's max comes from the DB row count)
        visible_rows <- reactive(label = "preview_visible_rows", {
            n_rows <- min(NROW(data()), max_rows)
            range <- as.integer(preview_rows())
            if (n_rows == 0L || length(range) != 2L || range[1] > n_rows) {
                integer(0)
            } else {
                seq.int(max(range[1], 1L), min(range[2], n_rows))
            }
        })

        n_selected <- reactive(label = "preview_n_selected", {
            sum(vapply(rows$modules, \(module) module$selected(), logical(1)))
        })

        # ------ MODULE --------------------------------------------------------

        # Initialize once: exactly one server per row, created the first time the row enters the range and kept
        # afterwards, independently of the rendering below. A dataset switch destroys the previous dataset's row
        # servers (session$destroy(): their observers, reactives, outputs and input values) AFTER this module
        # dropped its references to their reactives, so n_selected never reads a destroyed reactive.
        observeEvent(
            list(dataset_id(), visible_rows()),
            label = "preview_init_rows",
            {
                if (!identical(rows$dataset_id, dataset_id())) {
                    previous <- rows$modules
                    rows$modules <- list()
                    rows$dataset_id <- dataset_id()
                    lapply(previous, \(module) session$destroy(module$module_id))
                }
                req(dataset_id())

                new_rows <- setdiff(visible_rows(), as.integer(names(rows$modules)))
                # lapply, not a for loop: each row server must capture its own index
                new_modules <- lapply(new_rows, \(row_index) {
                    module_id <- preview_row_id(dataset_id(), row_index)
                    row_module <- preview_row_server(
                        module_id,
                        row_index = row_index,
                        data = data,
                        visible_rows = visible_rows
                    )
                    list(module_id = module_id, selected = row_module$selected)
                })
                names(new_modules) <- new_rows
                rows$modules <- c(rows$modules, new_modules)
            }
        )

        # ------ OUTPUT --------------------------------------------------------

        # Render many: the table lists the rows in range, the cells come from each row's own output
        output$table <- renderUI({
            req(length(visible_rows()) > 0L)
            tags$table(
                class = "preview-table",
                tags$thead(tags$tr(
                    tags$th(scope = "col", class = "preview-select"),
                    tags$th(scope = "col"),
                    lapply(names(data()), \(column) tags$th(scope = "col", column))
                )),
                tags$tbody(lapply(visible_rows(), \(row_index) {
                    preview_row_ui(ns(preview_row_id(dataset_id(), row_index)))
                }))
            )
        })

        output$caption <- renderText({
            n_rows <- NROW(data())
            req(n_rows > 0L)
            shown <- visible_rows()
            if (length(shown) == 0L) {
                return(tr("No rows to show"))
            }
            range_text <- if (n_rows > max_rows) {
                tr("Rows %s to %s of the first %s", min(shown), max(shown), max_rows)
            } else {
                tr("Rows %s to %s of %s", min(shown), max(shown), n_rows)
            }
            return(paste0(range_text, ". ", tr("%s selected", n_selected()), "."))
        })
    })
}

# Module id of a row server: the dataset id is part of it so that, after a dataset switch, the browser cannot
# replay the previous dataset's cached row output into a placeholder with the same id
preview_row_id <- function(dataset_id, row_index) {
    return(paste0("row_", dataset_id, "_", row_index))
}
