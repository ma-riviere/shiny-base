/**
 * Assertion helpers for E2E tests.
 *
 * Provides text-based assertions that minimize token cost when Claude reads test output.
 * Prefer these over screenshots for routine checks.
 *
 * Usage:
 *   const { assertText, assertVisible, assertCurrentPage } = require('./helpers/assertions');
 *   await assertText(page, '#title', 'Expected Title');
 */

// ---- TEXT ASSERTIONS --------------------------------------------------------

/**
 * Assert element contains expected text.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 * @param {string} expected - Expected text (substring match)
 * @param {Object} options
 * @param {boolean} options.exact - Require exact match (default: false)
 * @throws {Error} If assertion fails
 */
async function assertText(page, selector, expected, options = {}) {
    const { exact = false } = options;
    const element = await page.$(selector);
    if (!element) {
        throw new Error(`assertText: Element not found: ${selector}`);
    }
    const actual = await element.textContent();
    const matches = exact ? actual.trim() === expected : actual.includes(expected);
    if (!matches) {
        throw new Error(`assertText failed for "${selector}": expected "${expected}", got "${actual.trim()}"`);
    }
}

/**
 * Assert element text does NOT contain a string.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 * @param {string} unexpected - Text that should NOT be present
 */
async function assertTextAbsent(page, selector, unexpected) {
    const element = await page.$(selector);
    if (!element) return; // Element not present = text absent
    const actual = await element.textContent();
    if (actual.includes(unexpected)) {
        throw new Error(`assertTextAbsent failed for "${selector}": found "${unexpected}" in "${actual.trim()}"`);
    }
}

/**
 * Assert input has expected value.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector for input
 * @param {string} expected - Expected value
 */
async function assertInputValue(page, selector, expected) {
    const actual = await page.inputValue(selector);
    if (actual !== expected) {
        throw new Error(`assertInputValue failed for "${selector}": expected "${expected}", got "${actual}"`);
    }
}

// ---- VISIBILITY ASSERTIONS --------------------------------------------------

/**
 * Assert element is visible.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 * @throws {Error} If element is not visible
 */
async function assertVisible(page, selector) {
    const element = await page.$(selector);
    if (!element) {
        throw new Error(`assertVisible: Element not found: ${selector}`);
    }
    const visible = await element.isVisible();
    if (!visible) {
        throw new Error(`assertVisible failed: "${selector}" exists but is not visible`);
    }
}

/**
 * Assert element is hidden or does not exist.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 */
async function assertHidden(page, selector) {
    const element = await page.$(selector);
    if (element) {
        const visible = await element.isVisible();
        if (visible) {
            throw new Error(`assertHidden failed: "${selector}" is visible`);
        }
    }
    // Not found = hidden, which is fine
}

/**
 * Assert element exists in DOM (may be hidden).
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 */
async function assertExists(page, selector) {
    const element = await page.$(selector);
    if (!element) {
        throw new Error(`assertExists failed: "${selector}" not found in DOM`);
    }
}

/**
 * Assert element does NOT exist in DOM.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 */
async function assertNotExists(page, selector) {
    const element = await page.$(selector);
    if (element) {
        throw new Error(`assertNotExists failed: "${selector}" found in DOM`);
    }
}

// ---- STATE ASSERTIONS -------------------------------------------------------

/**
 * Assert element is enabled.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 */
async function assertEnabled(page, selector) {
    const element = await page.$(selector);
    if (!element) {
        throw new Error(`assertEnabled: Element not found: ${selector}`);
    }
    const disabled = await element.isDisabled();
    if (disabled) {
        throw new Error(`assertEnabled failed: "${selector}" is disabled`);
    }
}

/**
 * Assert element is disabled.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 */
async function assertDisabled(page, selector) {
    const element = await page.$(selector);
    if (!element) {
        throw new Error(`assertDisabled: Element not found: ${selector}`);
    }
    const disabled = await element.isDisabled();
    if (!disabled) {
        throw new Error(`assertDisabled failed: "${selector}" is enabled`);
    }
}

/**
 * Assert checkbox is checked.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 */
async function assertChecked(page, selector) {
    const checked = await page.isChecked(selector);
    if (!checked) {
        throw new Error(`assertChecked failed: "${selector}" is not checked`);
    }
}

/**
 * Assert checkbox is unchecked.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 */
async function assertUnchecked(page, selector) {
    const checked = await page.isChecked(selector);
    if (checked) {
        throw new Error(`assertUnchecked failed: "${selector}" is checked`);
    }
}

// ---- NAVIGATION ASSERTIONS --------------------------------------------------

/**
 * Assert current URL contains expected string.
 * @param {Page} page - Playwright page
 * @param {string} expected - Expected URL substring
 */
async function assertUrl(page, expected) {
    const url = page.url();
    if (!url.includes(expected)) {
        throw new Error(`assertUrl failed: expected URL to contain "${expected}", got "${url}"`);
    }
}

/**
 * Assert current URL does NOT contain string (e.g., not on auth0).
 * @param {Page} page - Playwright page
 * @param {string} unexpected - URL substring that should NOT be present
 */
async function assertUrlAbsent(page, unexpected) {
    const url = page.url();
    if (url.includes(unexpected)) {
        throw new Error(`assertUrlAbsent failed: URL contains "${unexpected}": ${url}`);
    }
}

/**
 * Assert page title.
 * @param {Page} page - Playwright page
 * @param {string} expected - Expected title (substring match)
 */
async function assertTitle(page, expected) {
    const title = await page.title();
    if (!title.includes(expected)) {
        throw new Error(`assertTitle failed: expected "${expected}", got "${title}"`);
    }
}

/**
 * Assert current navbar page is active.
 * @param {Page} page - Playwright page
 * @param {string} pageName - Expected active page (home, explore, model, admin)
 */
async function assertCurrentPage(page, pageName) {
    const active = await page.evaluate(() => {
        const el = document.querySelector('.nav-link.active[data-value]');
        return el ? el.getAttribute('data-value') : null;
    });
    if (active !== pageName) {
        throw new Error(`assertCurrentPage failed: expected "${pageName}", got "${active}"`);
    }
}

// ---- COUNT ASSERTIONS -------------------------------------------------------

/**
 * Assert element count matches expected.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 * @param {number} expected - Expected count
 */
async function assertCount(page, selector, expected) {
    const elements = await page.$$(selector);
    if (elements.length !== expected) {
        throw new Error(`assertCount failed for "${selector}": expected ${expected}, got ${elements.length}`);
    }
}

/**
 * Assert element count is greater than minimum.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 * @param {number} min - Minimum count
 */
async function assertMinCount(page, selector, min) {
    const elements = await page.$$(selector);
    if (elements.length < min) {
        throw new Error(`assertMinCount failed for "${selector}": expected >= ${min}, got ${elements.length}`);
    }
}

// ---- CLASS ASSERTIONS -------------------------------------------------------

/**
 * Assert element has a specific class.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 * @param {string} className - Expected class name
 */
async function assertHasClass(page, selector, className) {
    const element = await page.$(selector);
    if (!element) {
        throw new Error(`assertHasClass: Element not found: ${selector}`);
    }
    const hasClass = await element.evaluate((el, cls) => el.classList.contains(cls), className);
    if (!hasClass) {
        throw new Error(`assertHasClass failed: "${selector}" does not have class "${className}"`);
    }
}

/**
 * Assert element does NOT have a specific class.
 * @param {Page} page - Playwright page
 * @param {string} selector - CSS selector
 * @param {string} className - Class name that should be absent
 */
async function assertNoClass(page, selector, className) {
    const element = await page.$(selector);
    if (!element) return; // No element = no class
    const hasClass = await element.evaluate((el, cls) => el.classList.contains(cls), className);
    if (hasClass) {
        throw new Error(`assertNoClass failed: "${selector}" has class "${className}"`);
    }
}

module.exports = {
    // Text
    assertText,
    assertTextAbsent,
    assertInputValue,
    // Visibility
    assertVisible,
    assertHidden,
    assertExists,
    assertNotExists,
    // State
    assertEnabled,
    assertDisabled,
    assertChecked,
    assertUnchecked,
    // Navigation
    assertUrl,
    assertUrlAbsent,
    assertTitle,
    assertCurrentPage,
    // Count
    assertCount,
    assertMinCount,
    // Class
    assertHasClass,
    assertNoClass
};
