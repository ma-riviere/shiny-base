# Table / list utilities shared across modules.

# Build the JS for a `Shiny.setInputValue` call carrying a row id.
#
# Core of the "one observer for all rows" pattern: every row's handler targets
# the SAME input id; the value identifies the clicked row, so a single
# observeEvent handles them all. Attach the result to an element's `onclick`
# (a selectable row <div>, a <button>, ...).
#
# Two flavours:
#   - event = FALSE (default): stable SELECTION. Sends the bare value, which
#     Shiny deduplicates (re-setting to the same value is a no-op). It behaves
#     like any input and is bookmark-restorable. Read `input$<id>`.
#   - event = TRUE: repeatable ACTION. Sends a structured `{id}` payload with
#     `priority = 'event'`, so the handler fires on every click - even repeats of
#     the same row (delete, edit, ...). Read `input$<id>$id`. Exclude from
#     bookmarks.
#
# `priority = 'event'` is the idiomatic way to make a repeated identical value
# re-fire; it is equivalent in effect to (and replaces) forcing a change with a
# changing value such as `nonce: Date.now()`.
#
# @param input_id Namespaced input id (use `ns("...")`).
# @param value Row identifier(s), usually the primary key. Vectorized.
# @param event Repeatable action (TRUE) vs stable selection (FALSE). See above.
# @return Character vector of JS snippets (one per `value`).
set_input_js <- function(input_id, value, event = FALSE) {
    # encodeString quotes + escapes the value into a safe single-quoted JS string
    # literal, so ids with quotes/backslashes cannot break or inject (app ids are
    # integers, but this is reusable).
    value_js <- encodeString(as.character(value), quote = "'")

    set_value <- if (isTRUE(event)) {
        sprintf("{id: %s}, {priority: 'event'}", value_js)
    } else {
        value_js
    }

    sprintf("Shiny.setInputValue('%s', %s)", input_id, set_value)
}

# Create action button(s) for a row, wired with set_input_js() (event = TRUE).
#
# Render the result with `escape = FALSE` (DT) or insert via `htmltools::HTML()`.
#
# @inheritParams set_input_js
# @param label Optional button label text (HTML-escaped).
# @param icon Optional bsicons name (e.g. "trash").
# @param class Full CSS class string for the button.
# @param title Optional tooltip / aria-label (HTML-escaped).
# @return Character vector of HTML <button> strings (one per `value`).
create_table_action_button <- function(
    input_id,
    value,
    label = NULL,
    icon = NULL,
    class = "btn btn-sm btn-outline-secondary",
    title = NULL,
    event = TRUE
) {
    icon_html <- if (!is.null(icon)) as.character(bsicons::bs_icon(icon)) else ""
    label_html <- if (!is.null(label)) htmltools::htmlEscape(label) else ""
    sep <- if (nzchar(icon_html) && nzchar(label_html)) " " else ""
    inner <- paste0(icon_html, sep, label_html)

    title_attr <- if (!is.null(title)) {
        sprintf(' title="%s" aria-label="%s"', htmltools::htmlEscape(title), htmltools::htmlEscape(title))
    } else {
        ""
    }

    onclick <- set_input_js(input_id, value, event = event)

    sprintf(
        "<button type=\"button\" class=\"%s\"%s onclick=\"%s\">%s</button>",
        class,
        title_attr,
        onclick,
        inner
    )
}
