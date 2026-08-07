/**
 * UI interaction helpers for E2E tests.
 *
 * Provides reusable utilities for common Shiny/bslib UI patterns.
 *
 * Usage:
 *   const { clickButton, selectDropdown, fillInput } = require('./helpers/ui');
 *   await selectDropdown(page, 'dataset_select', '1');
 */
const { waitForReactivity } = require('./shiny');

// ---- BUTTONS ----------------------------------------------------------------

/**
 * Click a button and wait for reactivity.
 * @param {Page} page - Playwright page
 * @param {string} id - Button ID (without #)
 * @param {Object} options
 * @param {boolean} options.waitForReactivity - Wait after click (default: true)
 */
async function clickButton(page, id, options = {}) {
    const { waitForReactivity: doWait = true } = options;
    await page.click(`#${id}`);
    if (doWait) {
        await waitForReactivity(page);
    }
}

// ---- INPUTS -----------------------------------------------------------------

/**
 * Fill a text input.
 * @param {Page} page - Playwright page
 * @param {string} id - Input ID
 * @param {string} value - Text to enter
 * @param {Object} options
 * @param {boolean} options.clear - Clear existing text first (default: true)
 */
async function fillInput(page, id, value, options = {}) {
    const { clear = true } = options;
    const selector = `#${id}`;
    if (clear) {
        await page.fill(selector, '');
    }
    await page.fill(selector, value);
}

// ---- DROPDOWNS --------------------------------------------------------------

/**
 * Select an option from a selectInput/selectizeInput.
 * @param {Page} page - Playwright page
 * @param {string} id - Select element ID
 * @param {string} value - Option value to select
 * @param {Object} options
 * @param {boolean} options.waitForReactivity - Wait after selection (default: true)
 */
async function selectDropdown(page, id, value, options = {}) {
    const { waitForReactivity: doWait = true } = options;

    // Check if it's a selectize input (has sibling .selectize-control)
    const isSelectize = await page.$(`#${id} + .selectize-control`);

    if (isSelectize) {
        // For selectize: click control, then click option
        await page.click(`#${id} + .selectize-control .selectize-input`);
        await page.click(`.selectize-dropdown [data-value="${value}"]`);
    } else {
        // Standard select
        await page.selectOption(`#${id}`, value);
    }

    if (doWait) {
        await waitForReactivity(page);
    }
}

// ---- FILES ------------------------------------------------------------------

/**
 * Upload a file to a Shiny fileInput.
 * @param {Page} page - Playwright page
 * @param {string} id - File input ID (without #)
 * @param {string} filepath - Absolute path to file
 * @param {Object} options
 * @param {boolean} options.waitForCompleted - Wait for upload bar to complete (default: true)
 */
async function uploadFile(page, id, filepath, options = {}) {
    const { waitForCompleted = true } = options;

    // Shiny fileInput id points directly to the input[type="file"]
    // However, sometimes it's wrapped. We try the ID directly first.
    // Note: Playwright can handle hidden file inputs.
    const selector = `#${id}`;

    await page.setInputFiles(selector, filepath);

    if (waitForCompleted) {
        // Wait for progress bar to finish (Shiny pattern)
        await page.waitForSelector(`#${id}_progress.progress-bar-success`, { timeout: 30000 }).catch(() => {
            // Sometimes it goes too fast to catch, so we check if file-name is shown
            // Shiny displays filenames in the text input part
        });
        await waitForReactivity(page);
    }
}

module.exports = {
    clickButton,
    fillInput,
    selectDropdown,
    uploadFile
};
