# Dataset assistant server: one shinychat chat bound to the Explore page's
# current dataset. shinychat owns the streaming loop, the Stop button and the
# tool/thinking display; this module only rebinds the client when the dataset
# changes and keeps the running SQL query cancellable.
#
# @param dataset Reactive: the dataset row (NULL when nothing is selected)
# @param data Reactive: the parsed data.frame (NULL when nothing is selected)
dataset_chat_server <- function(id, dataset, data) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Shared with the tool closures: in-flight mirai + per-turn call counter
        state <- new.env(parent = emptyenv())
        state$tool_calls <- 0L
        state$query <- NULL

        current_language <- function() {
            # reactiveVal created by shiny.i18n::update_lang() (server.R apply_language); absent until then
            lang <- session$userData$shiny.i18n$lang
            if (is.null(lang)) getOption("default_language", "en") else lang() %||% getOption("default_language", "en")
        }

        chat_module <- shinychat::chat_server(
            "chat",
            client = dataset_chat_client(NULL, NULL, isolate(current_language()), state),
            history = FALSE
        )

        # ------ REACTIVE ------------------------------------------------------

        # Target snapshot, applied by the observer below. Indirection needed
        # because chat$clear() aborts while a response streams and set_client()
        # silently defers the swap: both must wait for an idle chat.
        pending <- reactiveVal(NULL)

        observeEvent(
            list(dataset(), data()),
            label = "dataset_chat_target",
            ignoreNULL = FALSE,
            {
                pending(list(dataset = dataset(), data = data(), language = isolate(current_language())))
            }
        )

        observeEvent(input$new_chat, label = "dataset_chat_new", {
            pending(list(dataset = dataset(), data = data(), language = isolate(current_language())))
        })

        observe(label = "dataset_chat_rebind", {
            target <- pending()
            req(!is.null(target), identical(chat_module$status(), "idle"))
            pending(NULL)
            state$tool_calls <- 0L
            # sync = FALSE: sync would copy the previous dataset's prompt and tool into the new client
            chat_module$set_client(
                dataset_chat_client(target$dataset, target$data, target$language, state),
                sync = FALSE
            )
            chat_module$clear()
            shinyjs::toggle("launcher", condition = !is.null(target$dataset))
            if (is.null(target$dataset)) {
                bslib::hide_offcanvas("panel", session = session)
            }
        })

        # Tool-call budget is per user turn
        observeEvent(chat_module$last_input(), label = "dataset_chat_turn_start", {
            state$tool_calls <- 0L
        })

        # shinychat's Stop button cancels the model stream, not the SQL query
        stop_query <- function() {
            if (!is.null(state$query)) {
                mirai::stop_mirai(state$query)
            }
        }
        observeEvent(input[["chat_cancel"]], label = "dataset_chat_stop_query", stop_query())
        session$onSessionEnded(stop_query)

        observeEvent(chat_module$last_error(), label = "dataset_chat_error", {
            log_warn("[CHAT] Assistant turn failed: {conditionMessage(chat_module$last_error())}")
        })
    })
}
