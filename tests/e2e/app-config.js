/**
 * App-specific E2E test configuration.
 *
 * This file contains constants and helpers specific to THIS app.
 * Generic helpers (helpers/*) should NOT import from this file.
 * Test files import both: helpers for generic actions, app-config for app-specific constants.
 *
 * Usage:
 *   const { PAGES, SELECTORS } = require('./app-config');
 *   const { navigateTo } = require('./helpers');
 *   await navigateTo(page, PAGES.EXPLORE);
 */

// App-specific page values (from R/001_navbar_ui.R)
const PAGES = {
    HOME: 'home',
    EXPLORE: 'explore',
    MODEL: 'model',
    ADMIN: 'admin',  // From shinyutils package, but still app-specific in terms of visibility
    // Admin sub-tabs (from shinyutils::admin_ui)
    ADMIN_SYSTEM: 'system',
    ADMIN_OTEL: 'otel',
    ADMIN_USERS: 'users'  // Auth0 users management (hidden for non-admin roles)
};

// App-specific element selectors (module namespaces)
const SELECTORS = {
    // Explore module (200_explore)
    explore: {
        datasetSelect: '#explore-dataset_select',
        dataTable: '#explore-data_table'
    },
    // Model module (300_model)
    model: {
        modelSelect: '#model-model_select',
        fitButton: '#model-fit_btn',
        saveButton: '#model-save_btn',
        modelSummary: '#model-summary'
    },
    // Home module (100_home)
    home: {
        // Add app-specific home selectors here
    },
    // Admin module (from shinyutils package)
    admin: {
        tabsNav: '#admin_panel-admin_tabs',
        systemTab: '.nav-link[data-value="system"]',
        otelTab: '.nav-link[data-value="otel"]',
        usersTab: '.nav-link[data-value="users"]'  // Hidden for non-admin roles
    }
};

// App-specific test helpers that use helpers/* internally
// Example: complex multi-step flows specific to this app

/**
 * Select a dataset in the explore module.
 * @param {Page} page - Playwright page
 * @param {string} datasetId - Dataset ID to select
 */
async function selectDataset(page, datasetId) {
    const { selectDropdown, waitForReactivity } = require('./helpers');
    await selectDropdown(page, 'explore-dataset_select', datasetId);
    await waitForReactivity(page);
}

/**
 * Fit a model with current settings.
 * @param {Page} page - Playwright page
 */
async function fitModel(page) {
    const { clickTaskButton } = require('./helpers');
    await clickTaskButton(page, 'model-fit_btn', { timeout: 120000 });
}

module.exports = {
    PAGES,
    SELECTORS,
    // App-specific helpers
    selectDataset,
    fitModel
};
