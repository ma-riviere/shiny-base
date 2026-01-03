/**
 * Playwright Test fixtures and custom extensions.
 *
 * Provides:
 * - Extended test with Shiny-specific fixtures
 * - Custom expect matchers for Shiny apps
 *
 * Usage in spec files:
 *   const { test, expect, shiny } = require('./helpers/fixtures');
 *
 *   test('example', async ({ page, shiny }) => {
 *       await shiny.waitForReady(page);
 *       await expect(page.locator('.navbar')).toBeVisible();
 *   });
 */
const { test: base, expect } = require('@playwright/test');
const { waitForShiny, waitForWaiterHide, waitForReactivity, waitForModal } = require('./shiny');
const { navigateTo, getCurrentPage } = require('./navigation');

/**
 * Extended test with Shiny-specific fixtures.
 */
const test = base.extend({
    // Shiny helper object available in all tests
    shiny: async ({ page }, use) => {
        const shinyHelpers = {
            /** Wait for Shiny to be fully connected */
            waitForReady: async () => {
                await waitForShiny(page);
                await waitForWaiterHide(page);
            },

            /** Wait for reactivity to settle after an action */
            waitForReactivity: async (buffer = 500) => {
                await waitForReactivity(page, buffer);
            },

            /** Wait for a modal to appear */
            waitForModal: async (options) => {
                await waitForModal(page, options);
            },

            /** Navigate to a page */
            navigateTo: async (pageName) => {
                await navigateTo(page, pageName);
            },

            /** Get current active page */
            getCurrentPage: async () => {
                return getCurrentPage(page);
            },

            /** Get Shiny input value */
            getInputValue: async (inputId) => {
                return page.evaluate((id) => Shiny.shinyapp.$inputValues[id], inputId);
            },

            /** Set Shiny input value programmatically */
            setInputValue: async (inputId, value, options = { priority: 'event' }) => {
                await page.evaluate(
                    ({ id, val, opts }) => Shiny.setInputValue(id, val, opts),
                    { id: inputId, val: value, opts: options }
                );
            },
        };

        await use(shinyHelpers);
    },
});


/**
 * Custom expect matchers for Shiny apps.
 *
 * Usage:
 *   await expect(page).toBeOnPage('explore');
 *   await expect(page.locator('#output')).not.toBeRecalculating();
 */
expect.extend({
    /**
     * Assert current page matches expected.
     * @param {Page} page - Playwright page
     * @param {string} expectedPage - Expected page value
     */
    async toBeOnPage(page, expectedPage) {
        const actual = await page.evaluate(() => {
            const el = document.querySelector('.nav-link.active[data-value]');
            return el ? el.getAttribute('data-value') : null;
        });

        const pass = actual === expectedPage;
        return {
            pass,
            message: () => pass
                ? `Expected not to be on page "${expectedPage}"`
                : `Expected to be on page "${expectedPage}", but was on "${actual}"`,
        };
    },

    /**
     * Assert Shiny output is not recalculating.
     * @param {Locator} locator - Element locator
     */
    async notToBeRecalculating(locator) {
        const hasClass = await locator.evaluate(el => el.classList.contains('recalculating'));
        const pass = !hasClass;
        return {
            pass,
            message: () => pass
                ? `Expected element to be recalculating`
                : `Expected element not to be recalculating, but it is`,
        };
    },

    /**
     * Assert URL does not contain substring.
     * @param {Page} page - Playwright page
     * @param {string} unexpected - Substring that should not be in URL
     */
    async toHaveURLNotContaining(page, unexpected) {
        const url = page.url();
        const pass = !url.includes(unexpected);
        return {
            pass,
            message: () => pass
                ? `Expected URL to contain "${unexpected}", but got "${url}"`
                : `Expected URL not to contain "${unexpected}", but got "${url}"`,
        };
    },
});

module.exports = { test, expect };
