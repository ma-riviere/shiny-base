/**
 * App-specific E2E test configuration.
 *
 * Keep this app's page names and selectors here; test files import these alongside the helpers.
 * Helpers stay independent of this file so they can be reused in other apps.
 * Add selectors when a test needs them, grouped by the R file that creates the element.
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
