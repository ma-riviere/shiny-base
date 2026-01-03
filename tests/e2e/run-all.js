/**
 * E2E test runner - orchestrates all tests with shared browser context.
 *
 * Usage:
 *   cd ~/.claude/skills/playwright && PROJECT_ROOT=/path/to/shiny-base node run.js /path/to/tests/e2e/run-all.js
 *
 * Environment:
 *   ROLE: admin | dev | user (default: dev)
 *   DEBUG: enable screenshots on failure
 *   TESTS: comma-separated test names to run (default: all)
 *          Example: TESTS=auth-login,explore-dataset
 */
const { chromium } = require('playwright');
const { getConfig, ensureAppRunning, login } = require('./helpers');
const fs = require('fs');
const path = require('path');

const role = process.env.ROLE || 'dev';
const debug = process.env.DEBUG === 'true' || process.env.DEBUG === '1';
const testsFilter = process.env.TESTS ? process.env.TESTS.split(',').map(t => t.trim()) : null;
const isCI = process.env.CI === 'true' || process.env.CI === '1';

// Discover test files (exclude helpers/, run-all.js)
function discoverTests(dir) {
    const files = fs.readdirSync(dir);
    return files
        .filter(f => f.endsWith('.js') && f !== 'run-all.js' && f !== 'app-config.js')
        .filter(f => !testsFilter || testsFilter.some(t => f.includes(t)))
        .map(f => ({
            name: f.replace('.js', ''),
            path: path.join(dir, f)
        }));
}

// Run a single test module
async function runTest(testPath, page, context) {
    // Tests export a run(page, context) function
    const testModule = require(testPath);
    if (typeof testModule.run !== 'function') {
        throw new Error(`Test must export run(page, context) function`);
    }
    await testModule.run(page, context);
}

(async () => {
    const startTime = Date.now();
    const config = getConfig();
    const testsDir = __dirname;
    const tests = discoverTests(testsDir);

    if (tests.length === 0) {
        console.log('No tests found.');
        process.exit(0);
    }

    console.log(`\n${'='.repeat(60)}`);
    console.log(`E2E Test Runner - Role: ${role}`);
    console.log(`${'='.repeat(60)}\n`);

    // Check app is running before proceeding
    await ensureAppRunning(config);

    console.log(`Found ${tests.length} test(s): ${tests.map(t => t.name).join(', ')}`);
    if (isCI) console.log('Running in CI mode (headless)');
    console.log('');

    const browser = await chromium.launch({
        headless: isCI,
        slowMo: isCI ? 0 : 50
    });
    const context = await browser.newContext();
    const page = await context.newPage();

    const results = { passed: [], failed: [] };

    try {
        // Login once, reuse session for all tests
        console.log('--- Setup: Login ---');
        await login(page, { role, debug });
        console.log('');

        // Run each test
        for (const test of tests) {
            console.log(`--- Test: ${test.name} ---`);
            try {
                await runTest(test.path, page, { config, role, debug });
                results.passed.push(test.name);
                console.log(`✓ ${test.name} PASSED\n`);
            } catch (error) {
                results.failed.push({ name: test.name, error: error.message });
                console.error(`✗ ${test.name} FAILED: ${error.message}`);
                if (debug) {
                    const screenshotPath = `/tmp/e2e-${test.name}-error.png`;
                    await page.screenshot({ path: screenshotPath, fullPage: true });
                    console.log(`  Screenshot: ${screenshotPath}`);
                }
                console.log('');
            }
        }

    } catch (error) {
        console.error('Setup failed:', error.message);
        if (debug) {
            await page.screenshot({ path: '/tmp/e2e-setup-error.png', fullPage: true });
        }
        process.exit(1);
    } finally {
        await browser.close();
    }

    // Summary
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`${'='.repeat(60)}`);
    console.log(`Results: ${results.passed.length} passed, ${results.failed.length} failed (${elapsed}s)`);
    console.log(`${'='.repeat(60)}`);

    if (results.failed.length > 0) {
        console.log('\nFailed tests:');
        results.failed.forEach(f => console.log(`  ✗ ${f.name}: ${f.error}`));
        process.exit(1);
    }

    console.log('\n✓ All tests passed');
})();
