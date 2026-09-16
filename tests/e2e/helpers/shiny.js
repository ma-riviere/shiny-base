/**
 * Shiny-specific helpers for E2E tests.
 *
 * Wait for connections, loading overlays and modal changes; read or set Shiny inputs.
 *
 * Usage:
 *   const { waitForShiny, waitForReactivity } = require('./helpers/shiny');
 *   await waitForShiny(page);
 */

/**
 * Wait until Shiny reports an active connection.
 * This does not check whether outputs have finished rendering.
 * @param {Page} page - Playwright page
 * @param {number} timeout - Max wait time in ms (default: 15000)
 */
async function waitForShiny(page, timeout = 15000) {
    await page.waitForFunction(
        () => window.Shiny && window.Shiny.shinyapp && window.Shiny.shinyapp.isConnected(),
        { timeout }
    );
}

/**
 * Wait for network idle, then allow a short delay for Shiny updates.
 * This is a fixed wait, not proof that all reactive work has finished.
 * @param {Page} page - Playwright page
 * @param {number} buffer - Additional wait after networkidle (default: 500ms)
 */
async function waitForReactivity(page, buffer = 500) {
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(buffer);
}

/**
 * Wait for waiter/loading overlay to disappear.
 * Checks multiple conditions: element removed, display none, opacity 0, or pointer-events none.
 * @param {Page} page - Playwright page
 * @param {number} timeout - Max wait time (default: 30000)
 */
async function waitForWaiterHide(page, timeout = 30000) {
    await page.waitForFunction(
        () => {
            const waiter = document.querySelector('.waiter-overlay');
            if (!waiter) return true;  // Element removed from DOM
            const style = window.getComputedStyle(waiter);
            // Check various hide conditions
            return (
                style.display === 'none' ||
                style.visibility === 'hidden' ||
                style.opacity === '0' ||
                style.pointerEvents === 'none' ||
                !waiter.offsetParent  // Not rendered (e.g., parent hidden)
            );
        },
        { timeout }
    );
}

/**
 * Wait for a modal to be visible.
 * @param {Page} page - Playwright page
 * @param {Object} options
 * @param {string} options.id - Modal element ID
 * @param {number} options.timeout - Max wait time (default: 5000)
 */
async function waitForModal(page, options = {}) {
    const { id, timeout = 5000 } = options;
    const selector = id ? `#${id}.modal.show` : '.modal.show';
    await page.waitForSelector(selector, { state: 'visible', timeout });
}

/**
 * Get current Shiny input value.
 * @param {Page} page - Playwright page
 * @param {string} inputId - Input ID (with namespace if needed)
 * @returns {Promise<any>} - Current input value
 */
async function getInputValue(page, inputId) {
    return page.evaluate((id) => Shiny.shinyapp.$inputValues[id], inputId);
}

/**
 * Set a Shiny input value programmatically.
 * @param {Page} page - Playwright page
 * @param {string} inputId - Input ID (with namespace if needed)
 * @param {any} value - Value to set
 * @param {Object} options - Shiny setInputValue options
 */
async function setInputValue(page, inputId, value, options = { priority: 'event' }) {
    await page.evaluate(
        ({ id, val, opts }) => Shiny.setInputValue(id, val, opts),
        { id: inputId, val: value, opts: options }
    );
}

module.exports = {
    waitForShiny,
    waitForReactivity,
    waitForWaiterHide,
    waitForModal,
    getInputValue,
    setInputValue
};
