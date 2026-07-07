/**
 * Auth0 flow tests (auth0r 0.2.0): logout confirmation skip via id_token_hint,
 * bookmark restoration through a login redirect, and concurrent logins from
 * two tabs (pending logins live in an encrypted transaction-map cookie, so one
 * tab's callback must not clobber the other's state).
 *
 * These flows need real Auth0: everything is skipped when BYPASS_AUTH0=TRUE.
 * Each test builds its own browser context (login flows can't share a page).
 */
const path = require('path');
const { execFileSync } = require('child_process');
const { test, expect } = require('@playwright/test');
const {
    getConfig, login,
    waitForShiny, waitForWaiterHide,
    navigateTo, getCurrentPage
} = require('./helpers');
const { PAGES } = require('./app-config');

const config = getConfig();

test.describe.configure({ mode: 'serial' });

const AUTH0_USERNAME_INPUT = 'input#username, input[name="username"], input[type="email"]';
const AUTH0_PASSWORD_INPUT = 'input#password, input[name="password"], input[type="password"]';
const AUTH0_SUBMIT_BUTTON = 'button[type="submit"], button[name="action"], button[data-action-button-primary="true"]';

/**
 * Fill and submit an Auth0 login form the page is already sitting on,
 * then wait for the redirect back to the app and for Shiny to connect.
 */
async function completeAuth0Login(page, creds) {
    await page.waitForSelector(AUTH0_USERNAME_INPUT, { timeout: 15000 });
    await page.fill(AUTH0_USERNAME_INPUT, creds.email);
    await page.fill(AUTH0_PASSWORD_INPUT, creds.password);
    await page.click(AUTH0_SUBMIT_BUTTON);
    await page.waitForURL(url => !url.toString().includes('auth0.com'), { timeout: 30000 });
    await waitForShiny(page);
}

/** Remove any open toasts (they overlay the user menu and intercept clicks). */
async function dismissToasts(page) {
    await page.evaluate(() => {
        document.querySelectorAll('.toast-container .toast').forEach(el => el.remove());
    });
}

/**
 * Poll shiny_bookmarks/ for a bookmark saved after `sinceMs` whose bookmarked
 * `nav` input is `navPage`. Parallel workers disconnect concurrently and each
 * writes a bookmark, so "newest directory" is not enough to identify ours;
 * the saved input state (read via Rscript) is.
 */
async function waitForBookmarkOnPage(sinceMs, navPage, timeoutMs = 20000) {
    const bookmarksDir = path.join(config.projectRoot, 'shiny_bookmarks');
    const rExpr = `
        dirs <- list.dirs("${bookmarksDir}", recursive = FALSE)
        dirs <- dirs[file.mtime(dirs) >= as.POSIXct(${Math.floor(sinceMs / 1000)})]
        dirs <- dirs[order(file.mtime(dirs), decreasing = TRUE)]
        for (dir in dirs) {
            inputs <- tryCatch(readRDS(file.path(dir, "input.rds")), error = function(e) NULL)
            if (identical(inputs$nav, "${navPage}")) { cat(basename(dir)); break }
        }`;
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        const id = execFileSync('Rscript', ['--vanilla', '-e', rExpr], { encoding: 'utf8' }).trim();
        if (id) return id;
        await new Promise(resolve => setTimeout(resolve, 1000));
    }
    throw new Error(`No bookmark with nav="${navPage}" saved after session disconnect`);
}

test.describe('Auth0 flows', () => {
    // These flows are role-agnostic (dev creds): run them once, on the dev project.
    test.beforeEach(({ }, testInfo) => {
        test.skip(config.bypassAuth0, 'Skipping: requires real Auth0 login');
        test.skip(testInfo.project.name !== 'dev', 'Skipping: not dev project');
    });

    test('logout skips the confirmation prompt (id_token_hint)', async ({ browser }) => {
        const context = await browser.newContext();
        const page = await context.newPage();
        await login(page, { role: 'dev' });
        await waitForWaiterHide(page);

        // Waiter overlays and toasts pop in asynchronously after login and
        // steal pointer events: dismiss and retry until the menu click lands.
        await expect(async () => {
            await dismissToasts(page);
            await page.click('.navbar .nav-link.dropdown-toggle:has(.user-nickname)', { timeout: 2000 });
            await page.waitForSelector('.dropdown-menu.show', { state: 'visible', timeout: 2000 });
        }).toPass({ timeout: 30000 });
        await page.click("[id='._auth0logout_']");

        // /v2/logout must chain straight back to the Auth0 login form: if the
        // tenant showed the end-user logout confirmation interstitial instead,
        // no username input would ever appear and this times out.
        await page.waitForURL(/auth0\.com/, { timeout: 15000 });
        await expect(page.locator(AUTH0_USERNAME_INPUT).first()).toBeVisible({ timeout: 15000 });
        await context.close();
    });

    test('bookmark restores through a login redirect', async ({ browser }) => {
        // Session 1: log in, navigate to explore, disconnect (bookmark saves
        // server-side in onSessionEnded).
        const sessionStart = Date.now();
        const ctx1 = await browser.newContext();
        const page1 = await ctx1.newPage();
        await login(page1, { role: 'dev' });
        await waitForWaiterHide(page1);
        await navigateTo(page1, PAGES.EXPLORE);
        await ctx1.close();

        const bookmarkId = await waitForBookmarkOnPage(sessionStart, PAGES.EXPLORE);

        // Session 2 (fresh context, not authenticated): the _state_id_ must
        // survive the round-trip through Auth0 (it rides inside the encrypted
        // state cookie) and native restoration must land back on explore.
        const ctx2 = await browser.newContext();
        const page2 = await ctx2.newPage();
        await page2.goto(`${config.targetUrl}/?_state_id_=${bookmarkId}`);
        await page2.waitForURL(/auth0\.com/, { timeout: 15000 });
        await completeAuth0Login(page2, config.credentials.dev);
        await waitForWaiterHide(page2);

        // auth0-helpers.js strips code/state/_state_id_ from the URL after
        // load, so the only observable proof of restoration is the active tab.
        expect(await getCurrentPage(page2)).toBe(PAGES.EXPLORE);
        await ctx2.close();
    });

    test('two tabs can log in concurrently', async ({ browser }) => {
        const context = await browser.newContext();
        const pageA = await context.newPage();
        const pageB = await context.newPage();

        // Start BOTH logins before completing either: each redirect stores a
        // separate pending transaction in the shared auth0_state cookie.
        await pageA.goto(config.targetUrl);
        await pageA.waitForURL(/auth0\.com/, { timeout: 15000 });
        await pageB.goto(config.targetUrl);
        await pageB.waitForURL(/auth0\.com/, { timeout: 15000 });

        // Complete tab A first: with a single-value state cookie (auth0r
        // 0.1.0) this would have clobbered tab B's pending state.
        await completeAuth0Login(pageA, config.credentials.dev);
        await completeAuth0Login(pageB, config.credentials.dev);

        for (const page of [pageA, pageB]) {
            expect(page.url()).not.toContain('auth0.com');
            expect(await page.evaluate(() => window.Shiny?.shinyapp?.isConnected())).toBe(true);
        }
        await context.close();
    });
});
