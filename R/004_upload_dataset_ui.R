upload_dataset_modal_ui <- function(ns) {
    modalDialog(
        title = tr("Upload Dataset"),
        size = "m",
        easyClose = TRUE,
        footer = tagList(
            shinyjs::disabled(
                actionButton(
                    ns("upload_btn"),
                    tr("Upload"),
                    class = "btn-primary i18n",
                    `data-key` = "Upload"
                )
            ),
            modalButton(tr("Cancel"))
        ),
        div(
            class = "upload-modal-content",
            # File upload area - uses dipsaus-style CSS dropzone, now with multiple = TRUE
            div(
                class = "mb-3",
                tags$label(
                    class = "form-label i18n",
                    `data-key` = "CSV File(s)",
                    tr("CSV File(s)")
                ),
                # Wrapper div that CSS will style as dropzone
                div(
                    class = "fancy-file-input",
                    `data-after-content` = tr("Drag & drop, or click Browse (max 10MB per file)"),
                    fileInput(
                        ns("file"),
                        label = NULL,
                        accept = c(".csv", "text/csv"),
                        buttonLabel = tr("Browse"),
                        placeholder = tr("No files selected"),
                        multiple = TRUE
                    )
                ),
                # Selected files display
                uiOutput(ns("selected_file_ui"))
            ),
            # Upload status/error
            uiOutput(ns("upload_status"))
        )
    )
}
