/* eslint-disable no-console */
const fs = require('fs');
const path = require('path');
const { test, expect } = require('./helpers/fixtures');
const { waitForShiny, waitForWaiterHide, login, getConfig, navigateTo, getCurrentPage } = require('./helpers');
const { uploadFile, fillInput, clickButton, setSliderRange, createToyDataset, deleteFile } = require('./helpers');
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

        // Click the dataset selection button, separate from its edit/download/delete buttons.
        await row.locator('.dataset-row-link').click();
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage).catch(() => { });

        // Check we are on explore page
        await expect(sharedPage.locator(`.navbar .nav-link[data-value="${PAGES.EXPLORE}"]`)).toHaveClass(/active/);

        // Check dataset name is shown in the explore page summary row
        await expect(sharedPage.locator('#explore-dataset_summary .dataset-name')).toContainText(datasetName);
    });

    test('data preview: row selection survives leaving and re-entering the slider range', async () => {
        // Each preview row is a module kept for the whole dataset selection (initialize once, gate while
        // hidden): a selected row that the range slider hides must come back selected.
        const rows = sharedPage.locator('.preview-table tbody tr');
        const caption = sharedPage.locator('#explore-preview-caption');
        const rowCheckbox = (nth) => rows.nth(nth - 1).locator('input[type=checkbox]');

        // The toy dataset has 6 rows: the default 1-10 range is clamped to 1-6
        await expect(rows).toHaveCount(6);
        await expect(caption).toContainText('Rows 1 to 6 of 6');
        await expect(caption).toContainText('0 selected');

        await rowCheckbox(2).check();
        await expect(caption).toContainText('1 selected');

        // Rows 4-6: row 2 leaves the DOM, its server and selection stay
        await setSliderRange(sharedPage, 'sidebar-preview_rows', 4, 6);
        await expect(rows).toHaveCount(3);
        await expect(caption).toContainText('Rows 4 to 6 of 6');
        await expect(caption).toContainText('1 selected');

        await setSliderRange(sharedPage, 'sidebar-preview_rows', 1, 6);
        await expect(rows).toHaveCount(6);
        await expect(rowCheckbox(2)).toBeChecked();
        await expect(rowCheckbox(1)).not.toBeChecked();
    });

    test('should fit a model (auto-saved)', async () => {
        await navigateTo(sharedPage, PAGES.MODEL);

        // Ensure inputs are visible
        await expect(sharedPage.locator('#model-equation')).toBeVisible();

        // Fill equation
        await fillInput(sharedPage, 'model-equation', 'mpg ~ wt');

        // Fit (toolbar button, disabled server-side while the async fit runs)
        await clickButton(sharedPage, 'model-fit_btn');

        // Check results section visible
        await expect(sharedPage.locator('#model-results_section')).toBeVisible({ timeout: 60000 });

        // Fit = saved: the delete button enables without a separate save step
        await expect(sharedPage.locator('#model-delete_btn')).toBeEnabled();
    });

    test('should delete model', async () => {
        // Delete (model was auto-saved by the fit)
        await clickButton(sharedPage, 'model-delete_btn');

        // Check cleaned up
        await expect(sharedPage.locator('#model-results_section')).toBeHidden();
        await expect(sharedPage.locator('#model-equation')).toHaveValue('');
    });

    test('should delete dataset', async () => {
        await navigateTo(sharedPage, PAGES.EXPLORE);
        await waitForShiny(sharedPage);

        // Use the summary row delete button which is available on Explore page
        // (row action buttons have no ids: select by their data-shiny-input target)
        await sharedPage.click('button[data-shiny-input="explore-actions-delete"]');

        // Confirm in modal
        await expect(sharedPage.locator('.modal')).toBeVisible();
        await clickButton(sharedPage, 'explore-actions-confirm_delete');

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
