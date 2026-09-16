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

// Handle every input_button() (R/helpers_inputs.R), including buttons added by later renders.
// data-shiny-input names the input; data-shiny-value carries the selected row ID.
// priority: 'event' sends repeated actions. Without it, Shiny ignores an unchanged selection.
// this.dataset reads HTML data-* attributes; it has no connection to the app's datasets.
$(document).on("click", "button[data-shiny-input]", function () {
    var options = this.dataset.shinyPriority ? { priority: this.dataset.shinyPriority } : undefined;
    Shiny.setInputValue(this.dataset.shinyInput, this.dataset.shinyValue, options);
});
