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
