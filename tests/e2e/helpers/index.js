/**
 * E2E test helpers - unified exports.
 *
 * Usage (raw Playwright):
 *   const { login, navigateTo, clickButton, assertText } = require('./helpers');
 *
 * Usage (@playwright/test):
 *   const { test, expect } = require('./helpers/fixtures');
 */

module.exports = {
    // Config
    ...require('./config'),

    // Auth
    ...require('./auth'),

    // Shiny-specific
    ...require('./shiny'),

    // Navigation
    ...require('./navigation'),

    // UI interactions
    ...require('./ui'),

    // Data generation
    ...require('./data'),

    // Assertions (legacy - prefer expect() from fixtures.js)
    ...require('./assertions')
};
