// Auth0 client-side helpers
// Cleans up URL after Auth0 callback (removes code/state/_state_id_ params)

$(document).on('shiny:connected', function () {
    var url = new URL(window.location.href);
    var params = url.searchParams;

    // Remove Auth0 callback params and bookmark state from URL display
    var hasParamsToRemove = params.has('code') || params.has('state') || params.has('_state_id_');
    if (hasParamsToRemove) {
        params.delete('code');
        params.delete('state');
        params.delete('_state_id_');
        // Rebuild clean URL
        var cleanUrl = url.origin + url.pathname;
        if (url.search) {
            cleanUrl += url.search;
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
