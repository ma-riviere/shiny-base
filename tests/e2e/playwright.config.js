/**
 * Playwright Test configuration.
 *
 * @see https://playwright.dev/docs/test-configuration
 */
const { defineConfig, devices } = require('@playwright/test');
const { getConfig } = require('./helpers/config');

// Load app config for base URL
const appConfig = getConfig();

module.exports = defineConfig({
    testDir: './',
    testMatch: '**/*.spec.js',

    // Timeout per test
    timeout: 60000,

    // Fail the build on CI if you accidentally left test.only in the source code
    forbidOnly: !!process.env.CI,

    // Retry on CI only
    retries: process.env.CI ? 2 : 0,

    // Parallel execution
    workers: process.env.CI ? 1 : 1, // Sequential for now (shared login state)

    // Reporter
    reporter: process.env.CI
        ? [['github'], ['html', { open: 'never' }]]
        : [['list'], ['html', { open: 'on-failure' }]],

    // Shared settings for all projects
    use: {
        baseURL: appConfig.targetUrl,
        trace: 'on-first-retry',
        screenshot: 'only-on-failure',
        video: 'retain-on-failure',

        // Browser options (use --headed flag to show browser for debugging)
        headless: true,
        actionTimeout: 10000,
        navigationTimeout: 30000,
    },

    // Global setup: login and save storage state
    globalSetup: require.resolve('./global-setup.js'),

    // Projects for different roles (auth handled in test beforeAll hooks)
    projects: [
        {
            name: 'dev',
            use: {
                ...devices['Desktop Chrome'],
            },
        },
        {
            name: 'admin',
            use: {
                ...devices['Desktop Chrome'],
            },
        },
        {
            name: 'user',
            use: {
                ...devices['Desktop Chrome'],
            },
        },
    ],

    // Run your local app before starting the tests (optional)
    // Uncomment if you want playwright to start the app
    // webServer: {
    //     command: 'R -e "shiny::runApp(port = 9090)"',
    //     url: appConfig.targetUrl,
    //     reuseExistingServer: !process.env.CI,
    //     timeout: 120000,
    // },
});
