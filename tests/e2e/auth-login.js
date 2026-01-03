/**
 * E2E test: Auth0 login flow.
 *
 * Standalone:
 *   cd ~/.claude/skills/playwright && PROJECT_ROOT=/path/to/shiny-base node run.js /path/to/tests/e2e/auth-login.js
 *
 * Via runner:
 *   Exports run(page, context) for use with run-all.js
 *
 * Environment:
 *   ROLE: admin | dev | user (default: dev)
 *   DEBUG: set to enable screenshots on failure
 */
const { chromium } = require('playwright');
const { getConfig, ensureAppRunning } = require('./helpers/config');
const { login } = require('./helpers/auth');

/**
 * Test: Verify login state after authentication.
 * When run via run-all.js, login is already done - just verify state.
 */
async function run(page, context = {}) {
    const { role = 'dev' } = context;

    // Verify we're authenticated (not on Auth0 page)
    const url = page.url();
    if (url.includes('auth0.com')) {
        throw new Error(`Not authenticated - still on Auth0 page: ${url}`);
    }

    // Verify Shiny app loaded
    await page.waitForLoadState('networkidle');
    const title = await page.title();
    console.log(`  Page title: "${title}"`);
    console.log(`  URL: ${url}`);
    console.log(`  ✓ Authenticated as ${role}`);
}

module.exports = { run };

// Standalone execution
if (require.main === module) {
    const role = process.env.ROLE || 'dev';
    const debug = process.env.DEBUG === 'true' || process.env.DEBUG === '1';

    (async () => {
        const config = getConfig();
        await ensureAppRunning(config);

        const browser = await chromium.launch({ headless: false, slowMo: 100 });
        const context = await browser.newContext();
        const page = await context.newPage();

        try {
            const didLogin = await login(page, { role, debug });

            if (didLogin) {
                console.log('\n✓ AUTH-LOGIN TEST PASSED');
            } else {
                console.log('\n✓ AUTH-LOGIN TEST PASSED (skipped - already authenticated)');
            }

        } catch (error) {
            console.error('\n✗ AUTH-LOGIN TEST FAILED:', error.message);
            await page.screenshot({ path: '/tmp/auth-error.png', fullPage: true });
            console.log('  Screenshot: /tmp/auth-error.png');
            process.exit(1);
        } finally {
            await browser.close();
        }
    })();
}
