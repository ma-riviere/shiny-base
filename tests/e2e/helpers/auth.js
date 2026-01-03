/**
 * Auth0 authentication helpers for E2E tests.
 *
 * Usage:
 *   const { login } = require('./helpers/auth');
 *   await login(page, { role: 'dev' });
 */
const { getConfig } = require('./config');

/**
 * Perform Auth0 login.
 * @param {Page} page - Playwright page object
 * @param {Object} options
 * @param {string} options.role - 'admin' | 'dev' | 'user'
 * @param {boolean} options.debug - Take screenshots for debugging
 * @returns {Promise<boolean>} - True if login performed, false if already authenticated
 */
async function login(page, options = {}) {
    const { role = 'dev', debug = false } = options;
    const config = getConfig();
    const creds = config.credentials[role];

    if (!creds.email || !creds.password) {
        throw new Error(`Missing credentials for role '${role}'. Check .Renviron`);
    }

    console.log(`Logging in as: ${role} (${creds.email})`);

    await page.goto(config.targetUrl, { waitUntil: 'networkidle', timeout: 30000 });

    const currentUrl = page.url();
    if (!currentUrl.includes('auth0.com')) {
        console.log('✓ Already authenticated or BYPASS_AUTH0=TRUE');
        return false;
    }

    console.log('  Redirected to Auth0 login page');
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2000);

    // Fill credentials
    const emailSelector = 'input#username, input[name="username"], input[type="email"], input[name="email"]';
    await page.waitForSelector(emailSelector, { timeout: 15000 });
    await page.fill(emailSelector, creds.email);
    console.log('  ✓ Email filled');

    const passwordSelector = 'input#password, input[name="password"], input[type="password"]';
    await page.fill(passwordSelector, creds.password);
    console.log('  ✓ Password filled');

    // Submit
    const submitSelector = 'button[type="submit"], button[name="action"], button[data-action-button-primary="true"]';
    await page.click(submitSelector);
    console.log('  ✓ Submit clicked');

    // Wait for redirect back to app
    await page.waitForURL(url => !url.toString().includes('auth0.com'), { timeout: 30000 });
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000); // Wait for Shiny to initialize

    // Verify we're back in the app
    const finalUrl = page.url();
    if (finalUrl.includes('auth0.com')) {
        if (debug) await page.screenshot({ path: '/tmp/auth-debug-stuck.png', fullPage: true });
        throw new Error(`Login failed: still on Auth0 page (${finalUrl})`);
    }

    console.log('✓ Login complete:', finalUrl);
    return true;
}

module.exports = { login };
