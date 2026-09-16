# Buttons shared by the dataset rows and saved-model picker.

# Every row sends its ID to the same Shiny input, so one observer handles all rows.
# www/js/app.js listens for clicks and passes these data attributes to Shiny.setInputValue().
#
# Two uses:
#   - Selection (event = FALSE): repeated clicks on the same row do nothing.
#     Shiny saves/restores the selected ID as a normal input.
#   - Action (event = TRUE): priority: 'event' sends every click, including repeats
#     on the same row (edit, delete, ...). Exclude these inputs from bookmarks.
#
# A native button supports keyboard focus and Enter/Space without extra JS.
# htmltools escapes attribute values, so names and IDs cannot become HTML or JS.
# The ID reaches R as a string: match it against as.character(ids) from the server's data.
# as.integer() would warn on malformed input, which fails tests under shinytest2's warn = 2.
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
        `data-shiny-value` = as.character(value),
        `data-shiny-priority` = if (isTRUE(event)) "event",
        ...
    ))
}
