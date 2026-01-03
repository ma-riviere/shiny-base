/**
 * Shiny-specific helpers for E2E tests.
 *
 * Provides utilities for waiting on Shiny's reactive system and UI states.
 *
 * Usage:
 *   const { waitForShiny, waitForReactivity } = require('./helpers/shiny');
 *   await waitForShiny(page);
 */

/**
 * Wait for Shiny app to be fully loaded and connected.
 * Checks for Shiny object and shiny:connected event.
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
 * Wait for Shiny reactivity to settle after an action.
 * Waits for network idle + a short buffer for reactive chain completion.
 * @param {Page} page - Playwright page
 * @param {number} buffer - Additional wait after networkidle (default: 500ms)
 */
async function waitForReactivity(page, buffer = 500) {
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(buffer);
}

/**
 * Wait for a Shiny output to have content (not empty/loading).
 * @param {Page} page - Playwright page
 * @param {string} outputId - Shiny output ID (without # or namespace)
 * @param {Object} options
 * @param {string} options.namespace - Module namespace prefix (e.g., 'home')
 * @param {number} options.timeout - Max wait time (default: 10000)
 */
async function waitForOutput(page, outputId, options = {}) {
    const { namespace = '', timeout = 10000 } = options;
    const fullId = namespace ? `${namespace}-${outputId}` : outputId;

    await page.waitForFunction(
        (id) => {
            const el = document.getElementById(id);
            if (!el) return false;
            // Check not recalculating
            if (el.classList.contains('recalculating')) return false;
            // Check has content
            return el.textContent.trim().length > 0;
        },
        fullId,
        { timeout }
    );
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
 * Wait for a modal to close.
 * @param {Page} page - Playwright page
 * @param {Object} options
 * @param {string} options.id - Modal element ID
 * @param {number} options.timeout - Max wait time (default: 5000)
 */
async function waitForModalClose(page, options = {}) {
    const { id, timeout = 5000 } = options;
    const selector = id ? `#${id}.modal` : '.modal.show';
    await page.waitForSelector(selector, { state: 'hidden', timeout });
}

/**
 * Execute JavaScript in Shiny context and return result.
 * @param {Page} page - Playwright page
 * @param {Function|string} fn - Function or JS code to execute
 * @returns {Promise<any>} - Result of execution
 */
async function evalShiny(page, fn) {
    return page.evaluate(fn);
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
    waitForOutput,
    waitForWaiterHide,
    waitForModal,
    waitForModalClose,
    evalShiny,
    getInputValue,
    setInputValue
};
