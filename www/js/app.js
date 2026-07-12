// Copy text to clipboard
// Optionally sends input$clipboard_copied to Shiny server for toast notifications
//
// Usage (UI):
//   <button onclick="copyToClipboard('some-id', 'ID copied!')">Copy ID</button>
//
// Usage (Server):
//   observeEvent(input$clipboard_copied, {
//       show_toast(input$clipboard_copied$msg, type = "success")
//   })
async function copyToClipboard(text, successMsg) {
    await navigator.clipboard.writeText(text);
    if (successMsg && window.Shiny) {
        Shiny.shinyapp.sendInput({ clipboard_copied: { text: text, msg: successMsg } });
    }
}

// Delegated click handler for input_button() (R/helpers_inputs.R): one
// document-level listener covers every such button in the app, wherever it is
// rendered and whatever input it targets (fully generic, nothing row- or
// dataset-specific). Sets the input named by `data-shiny-input` to
// `data-value`; `data-event` marks a repeatable action (priority: 'event'),
// otherwise the value is a stable, deduplicated selection.
// NB: `this.dataset` is the DOM API for data-* attributes (HTMLElement.dataset),
// unrelated to the app's "datasets".
$(document).on("click", "button[data-shiny-input]", function () {
    var options = this.dataset.event === "true" ? { priority: "event" } : undefined;
    Shiny.setInputValue(this.dataset.shinyInput, this.dataset.value, options);
});
