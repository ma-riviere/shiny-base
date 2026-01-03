/**
 * E2E test: Auth0 login flow.
 *
 * Standalone:
 *   node tests/e2e/auth-login.js
 *
 * Via runner:
 *   Exports run(page, context) for use with run-all.js
 *
 * Environment:
 *   ROLE: admin | dev | user (default: dev)
 *   DEBUG: set to enable screenshots on failure
 */
const { chromium } = require('playwright');
const {
    getConfig,
    ensureAppRunning,
    login,
    waitForShiny,
    waitForWaiterHide,
    assertUrlAbsent,
    assertVisible,
    getCurrentPage,
    isPageVisible
} = require('./helpers');
const { PAGES } = require('./app-config');

/**
 * Test: Verify login state after authentication.
 * When run via run-all.js, login is already done - just verify state.
 */
async function run(page, context = {}) {
    const { role = 'dev' } = context;

    // Verify we're authenticated (not on Auth0 page)
    await assertUrlAbsent(page, 'auth0.com');

    // Verify Shiny app loaded
    await waitForShiny(page);
    await waitForWaiterHide(page);

    // Verify navbar is visible
    await assertVisible(page, '.navbar');

    // Check current page
    const currentPage = await getCurrentPage(page);
    console.log(`  Current page: ${currentPage}`);

    // Check admin tab visibility based on role
    const adminVisible = await isPageVisible(page, PAGES.ADMIN);
    console.log(`  Admin tab visible: ${adminVisible}`);

    if (role === 'admin' && !adminVisible) {
        throw new Error('Admin role should see admin tab');
    }

    console.log(`  ✓ Authenticated as ${role}`);
}

module.exports = { run };

// Standalone execution
if (require.main === module) {
    const role = process.env.ROLE || 'dev';
    const debug = process.env.DEBUG === 'true' || process.env.DEBUG === '1';
    const isCI = process.env.CI === 'true' || process.env.CI === '1';

    (async () => {
        const config = getConfig();
        await ensureAppRunning(config);

        const browser = await chromium.launch({
            headless: isCI,
            slowMo: isCI ? 0 : 100
        });
        const browserContext = await browser.newContext();
        const page = await browserContext.newPage();

        try {
            await login(page, { role, debug });
            await run(page, { role });
            console.log('\n✓ AUTH-LOGIN TEST PASSED');
        } catch (error) {
            console.error('\n✗ AUTH-LOGIN TEST FAILED:', error.message);
            if (debug) {
                await page.screenshot({ path: '/tmp/auth-error.png', fullPage: true });
                console.log('  Screenshot: /tmp/auth-error.png');
            }
            process.exit(1);
        } finally {
            await browser.close();
        }
    })();
}
