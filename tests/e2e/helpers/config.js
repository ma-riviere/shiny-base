/**
 * Configuration helpers for E2E tests.
 *
 * Usage:
 *   const { getConfig, ensureAppRunning } = require('./helpers/config');
 *   const config = getConfig();
 *   await ensureAppRunning(config);
 */
const fs = require('fs');
const path = require('path');
const http = require('http');

/**
 * Parse .Renviron file (same format as .env).
 * @param {string} filepath - Path to .Renviron file
 * @returns {Object} Key-value pairs
 */
function loadRenviron(filepath) {
    const content = fs.readFileSync(filepath, 'utf8');
    const env = {};
    for (const line of content.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const match = trimmed.match(/^([^=]+)=(.*)$/);
        if (match) {
            env[match[1].trim()] = match[2].trim();
        }
    }
    return env;
}

/**
 * Get app configuration from .Renviron.
 * @returns {Object} Config with projectRoot, targetUrl, credentials
 */
function getConfig() {
    // PROJECT_ROOT can be set explicitly, or auto-detected from tests/e2e/ location
    const projectRoot = process.env.PROJECT_ROOT || path.resolve(__dirname, '../../..');

    const renvironPath = path.join(projectRoot, '.Renviron');
    if (!fs.existsSync(renvironPath)) {
        throw new Error(`Cannot find .Renviron at ${renvironPath}. Set PROJECT_ROOT if running from different location.`);
    }

    const renviron = loadRenviron(renvironPath);

    return {
        projectRoot,
        targetUrl: `http://127.0.0.1:${renviron.APP_PORT || 9090}`,
        credentials: {
            admin: { email: renviron.AUTH0_USER_ADMIN, password: renviron.AUTH0_PWD },
            dev: { email: renviron.AUTH0_USER_DEV, password: renviron.AUTH0_PWD },
            user: { email: renviron.AUTH0_USER, password: renviron.AUTH0_PWD }
        }
    };
}

/**
 * Check if the app is running at the expected URL.
 * @param {string} url - URL to check
 * @param {number} timeout - Timeout in ms (default: 5000)
 * @returns {Promise<boolean>}
 */
async function checkAppRunning(url, timeout = 5000) {
    return new Promise((resolve) => {
        const req = http.get(url, { timeout }, () => {
            // Any response (including redirects to Auth0) means app is running
            resolve(true);
        });
        req.on('error', () => resolve(false));
        req.on('timeout', () => {
            req.destroy();
            resolve(false);
        });
    });
}

/**
 * Verify app is running, exit with helpful message if not.
 * @param {Object} config - Config from getConfig()
 */
async function ensureAppRunning(config) {
    const isRunning = await checkAppRunning(config.targetUrl);
    if (!isRunning) {
        console.error(`\n✗ App not running at ${config.targetUrl}`);
        console.error(`\n  Start the app first:`);
        console.error(`    R -e "shiny::runApp(port = ${config.targetUrl.split(':').pop()})"\n`);
        process.exit(1);
    }
    console.log(`✓ App running at ${config.targetUrl}`);
}

module.exports = { loadRenviron, getConfig, checkAppRunning, ensureAppRunning };
