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
            # Dataset name input
            div(
                class = "mb-3",
                textInput(
                    ns("dataset_name"),
                    label = tagList(
                        tags$span(class = "i18n", `data-key` = "Dataset Name", tr("Dataset Name"))
                    ),
                    value = "",
                    placeholder = tr("Enter a name for your dataset")
                )
            ),
            # File upload area - uses dipsaus-style CSS dropzone
            div(
                class = "mb-3",
                tags$label(
                    class = "form-label i18n",
                    `data-key` = "CSV File",
                    tr("CSV File")
                ),
                # Wrapper div that CSS will style as dropzone
                div(
                    class = "fancy-file-input",
                    `data-after-content` = tr("Drag & drop, or click Browse (max 10MB)"),
                    fileInput(
                        ns("file"),
                        label = NULL,
                        accept = c(".csv", "text/csv"),
                        buttonLabel = tr("Browse"),
                        placeholder = tr("No file selected")
                    )
                ),
                # Selected file display
                uiOutput(ns("selected_file_ui"))
            ),
            # Upload status/error
            uiOutput(ns("upload_status"))
        )
    )
}
