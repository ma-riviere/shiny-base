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

// Shared pages from shinyutils (available in all apps using shiny-base template)
const SHARED_PAGES = {
    ADMIN: 'admin'
};

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

/**
 * Check if a specific page/tab is visible in the navbar.
 * Useful for testing permission-gated pages like admin.
 * @param {Page} page - Playwright page
 * @param {string} pageName - Page value to check
 * @returns {Promise<boolean>}
 */
async function isPageVisible(page, pageName) {
    const selector = `[data-value="${pageName}"]`;
    const element = await page.$(selector);
    return element !== null;
}

/**
 * Open the user dropdown menu in navbar.
 * @param {Page} page - Playwright page
 */
async function openUserMenu(page) {
    // User menu has the user-nickname class and is a nav-link dropdown-toggle
    await page.click('.navbar .nav-link.dropdown-toggle:has(.user-nickname)');
    await page.waitForSelector('.dropdown-menu.show', { state: 'visible' });
}

/**
 * Close any open dropdown menu.
 * @param {Page} page - Playwright page
 */
async function closeDropdowns(page) {
    // Click outside dropdowns to close them
    await page.click('body', { position: { x: 10, y: 10 } });
    await page.waitForSelector('.dropdown-menu.show', { state: 'hidden' }).catch(() => { });
}

/**
 * Open the profile modal from user menu.
 * @param {Page} page - Playwright page
 */
async function openProfile(page) {
    await openUserMenu(page);
    await page.click('#navbar-profile_link');
    await page.waitForSelector('.modal.show', { state: 'visible' });
}

/**
 * Change the app language via navbar selector.
 * @param {Page} page - Playwright page
 * @param {string} lang - Language code (e.g., 'en', 'fr')
 */
async function changeLanguage(page, lang) {
    // Language selector is a selectInput with id navbar-language
    await page.selectOption('#navbar-language', lang);
    await waitForReactivity(page);
}

/**
 * Get current language selection.
 * @param {Page} page - Playwright page
 * @returns {Promise<string>} - Current language code
 */
async function getCurrentLanguage(page) {
    return page.inputValue('#navbar-language');
}

module.exports = {
    SHARED_PAGES,
    navigateTo,
    getCurrentPage,
    isPageVisible,
    openUserMenu,
    closeDropdowns,
    openProfile,
    changeLanguage,
    getCurrentLanguage
};
