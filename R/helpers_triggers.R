# Event-based triggers for controlling reactive flow
#
# Lightweight alternative to gargoyle. Stores flags in session$userData for cross-module communication.
#
# Usage:
#   init("refresh_data", "show_modal")
#   trigger("refresh_data")
#   observe({ watch("refresh_data"); ... })
#   on("show_modal", { showModal(...) })

options(triggers.verbose = FALSE)

#' Initialize triggers (call once in server.R)
init <- function(..., session = shiny::getDefaultReactiveDomain()) {
    for (name in c(...)) {
        key <- paste0(".trigger_", name)
        if (is.null(session$userData[[key]])) {
            session$userData[[key]] <- shiny::reactiveVal(0L)
            if (getOption("triggers.verbose", FALSE)) {
                cat(sprintf("[trigger] init: %s\n", name), file = stderr())
            }
        }
    }
    invisible(session)
}

#' Fire a trigger
trigger <- function(name, session = shiny::getDefaultReactiveDomain()) {
    key <- paste0(".trigger_", name)
    flag <- session$userData[[key]]
    if (is.null(flag)) {
        cli::cli_abort("Trigger '{name}' not initialized.")
    }
    flag(flag() + 1L)
    if (getOption("triggers.verbose", FALSE)) {
        cat(sprintf("[trigger] fire: %s\n", name), file = stderr())
    }
    invisible(NULL)
}

#' Watch a trigger (creates reactive dependency)
watch <- function(name, session = shiny::getDefaultReactiveDomain()) {
    key <- paste0(".trigger_", name)
    flag <- session$userData[[key]]
    if (is.null(flag)) {
        cli::cli_abort("Trigger '{name}' not initialized.")
    }
    flag()
}

#' React to a trigger (wrapper around observeEvent)
on <- function(name, expr, session = shiny::getDefaultReactiveDomain(), ...) {
    key <- paste0(".trigger_", name)
    flag <- session$userData[[key]]
    if (is.null(flag)) {
        cli::cli_abort("Trigger '{name}' not initialized.")
    }
    shiny::observeEvent(
        flag(),
        substitute(expr),
        handler.quoted = TRUE,
        handler.env = parent.frame(),
        ignoreInit = TRUE,
        ...
    )
}
