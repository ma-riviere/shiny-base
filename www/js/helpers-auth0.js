// Auth0 client-side helpers
// Cleans up URL after Auth0 callback and detects session status for bookmark restoration offer.
//
// URL cleanup must happen on shiny:connected (after Shiny parses URL for bookmark restoration)
// but before the user sees the ugly auth params in the address bar.

$(document).on('shiny:connected', function () {
    // Clean up URL: remove Auth0 callback params and bookmark state
    // By this point, Shiny has already parsed _state_id_ for restoration
    var url = new URL(window.location.href);
    var params = url.searchParams;

    var hasParamsToRemove = params.has('code') || params.has('state') || params.has('_state_id_');
    if (hasParamsToRemove) {
        params.delete('code');
        params.delete('state');
        params.delete('_state_id_');

        // Rebuild clean URL
        var cleanUrl = url.origin + url.pathname;
        if (params.toString()) {
            cleanUrl += '?' + params.toString();
        }
        history.replaceState(null, '', cleanUrl);
    }

    // Detect fresh login vs page refresh using sessionStorage
    // sessionStorage is cleared when the tab closes, so absence = fresh login
    if (!sessionStorage.getItem('shiny_session_active')) {
        sessionStorage.setItem('shiny_session_active', 'true');
        Shiny.setInputValue('session_status', 'fresh_login');
    } else {
        Shiny.setInputValue('session_status', 'refresh');
    }
});
