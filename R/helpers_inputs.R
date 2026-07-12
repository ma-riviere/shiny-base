# Generic dynamic-interactivity helpers shared across modules.

# Build a <button> wired to the app-wide delegated click handler (www/js/app.js):
# clicking it sets the input named by `data-shiny-input` to `data-value`.
#
# Core of the "one observer for all rows" pattern: every row's button targets
# the SAME input id; the value identifies the clicked row, so a single
# observeEvent handles them all.
#
# Two flavours:
#   - event = FALSE (default): stable SELECTION. Sets the bare value, which
#     Shiny deduplicates (re-setting to the same value is a no-op). It behaves
#     like any input and is bookmark-restorable. Read `input$<id>`.
#   - event = TRUE: repeatable ACTION. Sets the value with `priority: 'event'`,
#     so the handler fires on every click - even repeats of the same row
#     (delete, edit, ...). Exclude from bookmarks.
#
# A native <button> gives Enter/Space activation, focus, and the button role
# for free (no role/tabindex/onkeydown wiring), and htmltools escapes every
# attribute, so ids/values/titles are injection-safe (unlike inline onclick
# strings). Server side, match the value with `as.character()` against the ids:
# it arrives as a string, and `as.integer()` warns on malformed input (fatal
# under shinytest2's `warn = 2`).
#
# @param input_id Namespaced input id (use `ns("...")`).
# @param value Row identifier, usually the primary key (scalar).
# @param ... Button content (icon, spans, ...) and/or extra attributes.
# @param event Repeatable action (TRUE) vs stable selection (FALSE). See above.
# @param class CSS class string for the button.
# @param title Optional tooltip text; also used as the aria-label.
input_button <- function(input_id, value, ..., event = FALSE, class = NULL, title = NULL) {
    return(tags$button(
        type = "button",
        class = class,
        title = title,
        `aria-label` = title,
        `data-shiny-input` = input_id,
        `data-value` = as.character(value),
        `data-event` = if (isTRUE(event)) "true",
        ...
    ))
}
