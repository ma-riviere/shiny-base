# Dataset assistant (sub-module of 200_explore): a floating launcher that opens
# a bslib::offcanvas() panel holding the shinychat widget. The launcher is
# hidden until a dataset is loaded (toggled by the server module).
dataset_chat_ui <- function(id) {
    ns <- NS(id)
    bslib::offcanvas(
        id = ns("panel"),
        class = "chat-panel",
        placement = "right",
        width = "26rem",
        backdrop = FALSE,
        scroll = TRUE,
        trigger = shinyjs::hidden(
            actionButton(
                ns("launcher"),
                tagList(
                    bsicons::bs_icon("chat-dots"),
                    tags$span(
                        class = "i18n",
                        `data-key` = "Ask about this dataset",
                        tr("Ask about this dataset")
                    )
                ),
                class = "btn-primary chat-launcher"
            )
        ),
        title = div(
            class = "d-flex align-items-center gap-2",
            tags$span(class = "i18n", `data-key` = "Dataset assistant", tr("Dataset assistant")),
            # Attributes cannot carry the i18n span markup tr() returns at UI build time: plain English
            tags$span(
                class = "text-muted",
                title = paste0("[", chat_provider_label(), "] ", getOption("chat_model")),
                `aria-label` = paste0("Model in use: ", getOption("chat_model")),
                bsicons::bs_icon("info-circle")
            ),
            actionButton(
                ns("new_chat"),
                tags$span(class = "i18n", `data-key` = "New chat", tr("New chat")),
                class = "btn-sm btn-outline-secondary text-nowrap"
            )
        ),
        shinychat::chat_ui(
            ns("chat"),
            placeholder = "Ask a question about this dataset",
            show_history = FALSE,
            drawer = FALSE,
            allow_attachments = FALSE,
            enable_cancel = TRUE,
            height = "100%"
        ),
        footer = tags$p(
            class = paste("mb-0", if (chat_is_local()) "text-success" else "text-warning"),
            if (chat_is_local()) {
                tr("100% private: your data stays on our own server.")
            } else {
                tr("Your question and dataset values go to an external provider.")
            }
        )
    )
}

# The platform's local model is reached on the `llm` Docker network (or a
# loopback tunnel in dev); anything else is an external provider.
chat_is_local <- function() {
    grepl("^https?://(llm|localhost|127\\.0\\.0\\.1)([:/]|$)", getOption("chat_base_url", ""))
}

chat_provider_label <- function() {
    if (chat_is_local()) "local" else "external"
}
