// Handle Enter key in modal dialogs to click the primary action button
$(document).on('keydown', '.modal', function (e) {
    if (e.key !== 'Enter') return;

    // Skip if focus is on a textarea or a button (let default behavior happen)
    var activeEl = document.activeElement;
    if (activeEl && (activeEl.tagName === 'TEXTAREA' || activeEl.tagName === 'BUTTON')) {
        return;
    }

    // Find the primary action button in the modal footer
    // Priority: btn-primary (Upload, OK), then btn-danger (Delete/Supprimer)
    var modal = $(this);
    var primaryBtn = modal.find('.modal-footer .btn-primary:visible:not(:disabled)').first();
    if (primaryBtn.length === 0) {
        primaryBtn = modal.find('.modal-footer .btn-danger:visible:not(:disabled)').first();
    }

    if (primaryBtn.length > 0) {
        e.preventDefault();
        primaryBtn.click();
    }
});
