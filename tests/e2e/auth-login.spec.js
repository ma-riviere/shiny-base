/**
 * E2E tests: Auth0 login and authentication state.
 *
 * Uses serial mode with a shared browser context that stays logged in.
 * Login happens once at the start of each describe block.
 *
 * Run:
 *   npx playwright test auth-login.spec.js
 *   npx playwright test auth-login.spec.js --project=admin
 */
const { test, expect } = require('./helpers/fixtures');
const { waitForShiny, waitForWaiterHide, login, getConfig, navigateTo } = require('./helpers');
const { PAGES, SELECTORS } = require('./app-config');

// Serial mode: tests run sequentially, sharing state
test.describe.configure({ mode: 'serial' });

// ----- AUTHENTICATION & RBAC - DEV ROLE --------------------------------------
// Tests for dev role: login, basic navigation, and RBAC permissions
// Merged into single describe to share browser session (avoids re-login)

test.describe('Authentication & RBAC - Dev role', () => {
    let sharedPage;
    const config = getConfig();

    test.beforeAll(async ({ browser }) => {
        // Create a context and page that will be shared across tests
        const context = await browser.newContext();
        sharedPage = await context.newPage();

        // Login if not bypassing Auth0
        if (!config.bypassAuth0) {
            await login(sharedPage, { role: 'dev' });
        } else {
            await sharedPage.goto(config.targetUrl);
        }
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage);
    });

    test.afterAll(async () => {
        await sharedPage.context().close();
    });

    // ----- Authentication tests -----

    test('should be authenticated after login', async () => {
        // Verify not on Auth0 page
        await expect(sharedPage).toHaveURLNotContaining('auth0.com');

        // Verify navbar is visible (app loaded)
        await expect(sharedPage.locator('.navbar')).toBeVisible();
    });

    test('should show correct navbar tabs', async () => {
        // All roles should see home, explore, model
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.HOME}"]`)).toBeVisible();
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.EXPLORE}"]`)).toBeVisible();
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.MODEL}"]`)).toBeVisible();
    });

    test('should be on home page by default', async () => {
        await expect(sharedPage).toBeOnPage(PAGES.HOME);
    });

    // ----- RBAC tests for dev role -----

    test('should see admin tab (ENV=dev grants admin)', async () => {
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.ADMIN}"]`)).toBeVisible();
    });

    test('should see system and otel sub-tabs in admin panel', async () => {
        await navigateTo(sharedPage, PAGES.ADMIN);

        await expect(sharedPage.locator(SELECTORS.admin.systemTab)).toBeVisible();
        await expect(sharedPage.locator(SELECTORS.admin.otelTab)).toBeVisible();
    });

    test('should NOT see users sub-tab (requires real admin role)', async () => {
        // Dev mode doesn't grant access to Auth0 users management
        await expect(sharedPage.locator(SELECTORS.admin.usersTab)).not.toBeVisible();
    });

});

// ----- RBAC - ADMIN ROLE -----------------------------------------------------
// Tests for actual admin role (requires --project=admin)

test.describe('RBAC - Admin role', () => {
    let sharedPage;
    const config = getConfig();

    test.beforeAll(async ({ browser }, testInfo) => {
        if (testInfo.project.name !== 'admin') {
            test.skip();
            return;
        }

        const context = await browser.newContext();
        sharedPage = await context.newPage();

        if (!config.bypassAuth0) {
            await login(sharedPage, { role: 'admin' });
        } else {
            await sharedPage.goto(config.targetUrl);
        }
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage);
    });

    test.afterAll(async () => {
        if (sharedPage) {
            await sharedPage.context().close();
        }
    });

    test('should see admin tab', async ({ }, testInfo) => {
        if (testInfo.project.name !== 'admin') test.skip();
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.ADMIN}"]`)).toBeVisible();
    });

    test('should see ALL admin sub-tabs including users', async ({ }, testInfo) => {
        if (testInfo.project.name !== 'admin') test.skip();

        await navigateTo(sharedPage, PAGES.ADMIN);

        await expect(sharedPage.locator(SELECTORS.admin.systemTab)).toBeVisible();
        await expect(sharedPage.locator(SELECTORS.admin.otelTab)).toBeVisible();
        await expect(sharedPage.locator(SELECTORS.admin.usersTab)).toBeVisible();
    });

});

// ----- RBAC - USER ROLE ------------------------------------------------------
// Tests for regular user role (requires --project=user)

test.describe('RBAC - User role', () => {
    let sharedPage;
    const config = getConfig();

    test.beforeAll(async ({ browser }, testInfo) => {
        if (testInfo.project.name !== 'user') {
            test.skip();
            return;
        }

        const context = await browser.newContext();
        sharedPage = await context.newPage();

        if (!config.bypassAuth0) {
            await login(sharedPage, { role: 'user' });
        } else {
            await sharedPage.goto(config.targetUrl);
        }
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage);
    });

    test.afterAll(async () => {
        if (sharedPage) {
            await sharedPage.context().close();
        }
    });

    test('should NOT see admin tab', async ({ }, testInfo) => {
        if (testInfo.project.name !== 'user') test.skip();
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.ADMIN}"]`)).not.toBeVisible();
    });

});
