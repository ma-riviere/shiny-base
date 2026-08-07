/**
 * Navigation helpers for E2E tests.
 *
 * Generic helpers for bslib page_navbar navigation.
 * Works with any app using shinyutils patterns (auth0, admin panel, etc.).
 *
 * Usage:
 *   const { navigateTo, getCurrentPage } = require('./helpers/navigation');
 *   await navigateTo(page, 'explore');
 */
const { waitForReactivity, waitForWaiterHide } = require('./shiny');

/**
 * Navigate to a specific page/tab in the navbar.
 * @param {Page} page - Playwright page
 * @param {string} pageName - Page value (home, explore, model, admin)
 * @param {Object} options
 * @param {boolean} options.waitForLoad - Wait for page content to load (default: true)
 * @param {number} options.timeout - Max wait time (default: 10000)
 */
async function navigateTo(page, pageName, options = {}) {
    const { waitForLoad = true, timeout = 10000 } = options;

    // Wait for any waiter overlay to hide before interacting
    await waitForWaiterHide(page).catch(() => { });

    // Click navbar link matching the page value
    // Use specific selector targeting main navbar to avoid conflicts with sub-tabs
    const selector = `.navbar .nav-link[data-value="${pageName}"]`;
    await page.waitForSelector(selector, { timeout });
    await page.click(selector);

    if (waitForLoad) {
        await waitForReactivity(page);
        // Some pages show waiter on first load
        await waitForWaiterHide(page).catch(() => { });
    }
}

/**
 * Get the current active page value.
 * @param {Page} page - Playwright page
 * @returns {Promise<string>} - Current page value (e.g., 'home', 'explore')
 */
async function getCurrentPage(page) {
    return page.evaluate(() => {
        const active = document.querySelector('.nav-link.active[data-value]');
        return active ? active.getAttribute('data-value') : null;
    });
}

module.exports = {
    navigateTo,
    getCurrentPage
};
