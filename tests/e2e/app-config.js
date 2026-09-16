/**
 * App-specific E2E test configuration.
 *
 * Constants specific to THIS app. Generic helpers (helpers/*) should NOT
 * import from this file; test files import both. Only what a spec uses lives
 * here: add a selector when a test needs it, next to the R file that owns it.
 *
 * Usage:
 *   const { PAGES, SELECTORS } = require('./app-config');
 *   const { navigateTo } = require('./helpers');
 *   await navigateTo(page, PAGES.EXPLORE);
 */

// Navbar page values (from R/001_navbar_ui.R; admin from shinyutils::admin_ui)
const PAGES = {
    HOME: 'home',
    EXPLORE: 'explore',
    MODEL: 'model',
    ADMIN: 'admin'
};

const SELECTORS = {
    // Admin sub-tabs (from shinyutils::admin_ui)
    admin: {
        systemTab: '.nav-link[data-value="system"]',
        otelTab: '.nav-link[data-value="otel"]',
        usersTab: '.nav-link[data-value="users"]'  // Hidden for non-admin roles
    }
};

module.exports = {
    PAGES,
    SELECTORS
};
