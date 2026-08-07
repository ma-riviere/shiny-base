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

    // Only run for 'dev' project
    test.beforeEach(({ }, testInfo) => {
        test.skip(testInfo.project.name !== 'dev', 'Skipping: not dev project');
    });

    test.beforeAll(async ({ browser }, testInfo) => {
        // Skip setup for non-matching projects
        if (testInfo.project.name !== 'dev') return;

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

    test.afterAll(async ({ }, testInfo) => {
        if (testInfo.project.name !== 'dev' || !sharedPage) return;
        await sharedPage.context().close();
    });

    // ----- Authentication tests -----

    test('should be authenticated and land on home with all navbar tabs', async () => {
        // Verify not on Auth0 page
        await expect(sharedPage).toHaveURLNotContaining('auth0.com');

        // Home page is the default after login
        await expect(sharedPage).toBeOnPage(PAGES.HOME);

        // All roles should see home, explore, model
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.HOME}"]`)).toBeVisible();
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.EXPLORE}"]`)).toBeVisible();
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.MODEL}"]`)).toBeVisible();
    });

    // ----- RBAC tests for dev role -----

    test('should see admin tab with system and otel sub-tabs (ENV=dev grants admin)', async () => {
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.ADMIN}"]`)).toBeVisible();
        await navigateTo(sharedPage, PAGES.ADMIN);

        await expect(sharedPage.locator(SELECTORS.admin.systemTab)).toBeVisible();
        await expect(sharedPage.locator(SELECTORS.admin.otelTab)).toBeVisible();
    });

    test('should NOT see users sub-tab (requires real admin role)', async () => {
        test.skip(config.bypassAuth0, 'Skipping: RBAC tests require Auth0');
        // Dev mode doesn't grant access to Auth0 users management
        await expect(sharedPage.locator(SELECTORS.admin.usersTab)).not.toBeVisible();
    });

});

// ----- RBAC - ADMIN ROLE -----------------------------------------------------
// Tests for actual admin role (requires --project=admin)
// Skipped when AUTH0_DISABLE=true (no real user roles)

test.describe('RBAC - Admin role', () => {
    let sharedPage;
    const config = getConfig();

    // Only run for 'admin' project with real Auth0
    test.beforeEach(({ }, testInfo) => {
        test.skip(config.bypassAuth0, 'Skipping: RBAC tests require Auth0');
        test.skip(testInfo.project.name !== 'admin', 'Skipping: not admin project');
    });

    test.beforeAll(async ({ browser }, testInfo) => {
        // Skip setup for non-matching projects or bypass mode
        if (testInfo.project.name !== 'admin' || config.bypassAuth0) return;

        const context = await browser.newContext();
        sharedPage = await context.newPage();

        await login(sharedPage, { role: 'admin' });
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage);
    });

    test.afterAll(async ({ }, testInfo) => {
        if (testInfo.project.name !== 'admin' || config.bypassAuth0 || !sharedPage) return;
        await sharedPage.context().close();
    });

    test('should see admin tab with ALL sub-tabs including users', async () => {
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.ADMIN}"]`)).toBeVisible();
        await navigateTo(sharedPage, PAGES.ADMIN);

        await expect(sharedPage.locator(SELECTORS.admin.systemTab)).toBeVisible();
        await expect(sharedPage.locator(SELECTORS.admin.otelTab)).toBeVisible();
        await expect(sharedPage.locator(SELECTORS.admin.usersTab)).toBeVisible();
    });

});

// ----- RBAC - USER ROLE ------------------------------------------------------
// Tests for regular user role (requires --project=user)
// Skipped when AUTH0_DISABLE=true (no real user roles)

test.describe('RBAC - User role', () => {
    let sharedPage;
    const config = getConfig();

    // Only run for 'user' project with real Auth0
    test.beforeEach(({ }, testInfo) => {
        test.skip(config.bypassAuth0, 'Skipping: RBAC tests require Auth0');
        test.skip(testInfo.project.name !== 'user', 'Skipping: not user project');
    });

    test.beforeAll(async ({ browser }, testInfo) => {
        // Skip setup for non-matching projects or bypass mode
        if (testInfo.project.name !== 'user' || config.bypassAuth0) return;

        const context = await browser.newContext();
        sharedPage = await context.newPage();

        await login(sharedPage, { role: 'user' });
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage);
    });

    test.afterAll(async ({ }, testInfo) => {
        if (testInfo.project.name !== 'user' || config.bypassAuth0 || !sharedPage) return;
        await sharedPage.context().close();
    });

    test('should NOT see admin tab', async () => {
        await expect(sharedPage.locator(`.nav-link[data-value="${PAGES.ADMIN}"]`)).not.toBeVisible();
    });

});
