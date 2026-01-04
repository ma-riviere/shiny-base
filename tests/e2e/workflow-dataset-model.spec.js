/* eslint-disable no-console */
const fs = require('fs');
const path = require('path');
const { test, expect } = require('./helpers/fixtures');
const { waitForShiny, waitForWaiterHide, login, getConfig, navigateTo, getCurrentPage } = require('./helpers');
const { uploadFile, fillInput, clickButton, clickTaskButton, createToyDataset, deleteFile } = require('./helpers');
const { PAGES } = require('./app-config');

test.describe.serial('Workflow: Dataset and Model', () => {
    // Shared state
    let sharedPage;
    let datasetName = `test_dataset_${Date.now()}`;
    let csvPath;

    const config = getConfig();

    test.beforeAll(async ({ browser }) => {
        // Create context and page
        const context = await browser.newContext();
        sharedPage = await context.newPage();

        // Login as dev
        if (!config.bypassAuth0) {
            await login(sharedPage, { role: 'dev' });
        } else {
            await sharedPage.goto(config.targetUrl);
        }
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage);

        // create toy csv
        csvPath = createToyDataset(datasetName);
    });

    test.afterAll(async () => {
        if (sharedPage) await sharedPage.close();
        if (csvPath) deleteFile(csvPath);
    });

    test('should upload a new dataset', async () => {
        await navigateTo(sharedPage, PAGES.HOME);

        await clickButton(sharedPage, 'home-open_upload');
        // Wait for modal
        await expect(sharedPage.locator('.modal')).toBeVisible();

        await uploadFile(sharedPage, 'upload-file', csvPath);

        await clickButton(sharedPage, 'upload-upload_btn');
        // Wait for modal to close (upload success)
        await expect(sharedPage.locator('.modal')).not.toBeVisible();
    });

    test('should see dataset in list and navigate to explore', async () => {
        // Find row with dataset name
        const row = sharedPage.locator('.dataset-row').filter({ hasText: datasetName }).first();
        await expect(row).toBeVisible();

        // Click the link part
        await row.locator('.dataset-row-link').click();
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage).catch(() => { });

        // Check we are on explore page
        await expect(sharedPage.locator(`.navbar .nav-link[data-value="${PAGES.EXPLORE}"]`)).toHaveClass(/active/);

        // Check dataset name is shown in explore page
        // 'summary_row' shows name. selector: #explore-summary_row-name
        await expect(sharedPage.locator('#explore-summary_row-name')).toContainText(datasetName);
    });

    test('should fit a model', async () => {
        await navigateTo(sharedPage, PAGES.MODEL);

        // Ensure inputs are visible
        await expect(sharedPage.locator('#model-equation')).toBeVisible();

        // Fill equation
        await fillInput(sharedPage, 'model-equation', 'mpg ~ wt');

        // Fit
        await clickTaskButton(sharedPage, 'model-fit_btn', { waitForComplete: true });

        // Check results section visible
        await expect(sharedPage.locator('#model-results_section')).toBeVisible();
        await expect(sharedPage.locator('#model-save_btn')).toBeEnabled();
    });

    test('should save and delete model', async () => {
        // Save
        await clickButton(sharedPage, 'model-save_btn');

        // Check delete button enabled
        await expect(sharedPage.locator('#model-delete_btn')).toBeEnabled();

        // Delete
        await clickButton(sharedPage, 'model-delete_btn');

        // Check cleaned up
        await expect(sharedPage.locator('#model-results_section')).toBeHidden();
        await expect(sharedPage.locator('#model-equation')).toHaveValue('');
    });

    test('should delete dataset', async () => {
        await navigateTo(sharedPage, PAGES.EXPLORE);
        await waitForShiny(sharedPage);

        // Use the summary row delete button which is available on Explore page
        await clickButton(sharedPage, 'explore-summary_row-delete');

        // Confirm in modal
        await expect(sharedPage.locator('.modal')).toBeVisible();
        await clickButton(sharedPage, 'explore-summary_row-confirm_delete');

        // Should nav home automatically due to callback
        await waitForShiny(sharedPage);

        const page = await getCurrentPage(sharedPage);
        await expect(sharedPage.locator(`.navbar .nav-link[data-value="${PAGES.HOME}"]`)).toHaveClass(/active/);
    });

    test('should verify dataset is gone', async () => {
        const row = sharedPage.locator('.dataset-row').filter({ hasText: datasetName });
        await expect(row).toHaveCount(0);
    });
});
