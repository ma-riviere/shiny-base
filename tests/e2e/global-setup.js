/**
 * Global setup for Playwright tests.
 *
 * Runs once before all tests:
 * - Ensures app is running
 */
const { getConfig, ensureAppRunning } = require('./helpers');

module.exports = async function globalSetup() {
    const config = getConfig();

    // Ensure app is running
    await ensureAppRunning(config);

    console.log('--- Global Setup Complete ---\n');
};
