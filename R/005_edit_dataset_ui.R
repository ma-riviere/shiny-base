# Rename dataset modal UI (following same pattern as upload_dataset_modal_ui)
edit_dataset_modal_ui <- function(ns, current_name = "") {
    modalDialog(
        title = tr("Rename Dataset"),
        size = "s",
        easyClose = TRUE,
        footer = tagList(
            actionButton(
                ns("confirm_rename"),
                tr("Rename"),
                class = "btn-primary i18n",
                `data-key` = "Rename"
            ),
            modalButton(tr("Cancel"))
        ),
        textInput(
            ns("new_dataset_name"),
            label = tr("New Name"),
            value = current_name,
            placeholder = tr("Enter new dataset name")
        )
    )
}
