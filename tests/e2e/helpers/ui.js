/**
 * UI interaction helpers for E2E tests.
 *
 * Provides reusable utilities for common Shiny/bslib UI patterns.
 *
 * Usage:
 *   const { clickButton, selectDropdown, fillInput } = require('./helpers/ui');
 *   await selectDropdown(page, 'dataset_select', '1');
 */
const { waitForReactivity } = require('./shiny');

// ---- BUTTONS ----------------------------------------------------------------

/**
 * Click a button and wait for reactivity.
 * @param {Page} page - Playwright page
 * @param {string} id - Button ID (without #)
 * @param {Object} options
 * @param {boolean} options.waitForReactivity - Wait after click (default: true)
 */
async function clickButton(page, id, options = {}) {
    const { waitForReactivity: doWait = true } = options;
    await page.click(`#${id}`);
    if (doWait) {
        await waitForReactivity(page);
    }
}

/**
 * Click an action button (Shiny actionButton).
 * Same as clickButton but semantic naming.
 * @param {Page} page - Playwright page
 * @param {string} id - Button ID
 */
async function clickActionButton(page, id) {
    await clickButton(page, id);
}

/**
 * Click a task button (bslib input_task_button) and optionally wait for completion.
 * @param {Page} page - Playwright page
 * @param {string} id - Button ID
 * @param {Object} options
 * @param {boolean} options.waitForComplete - Wait for button to return to ready state (default: true)
 * @param {number} options.timeout - Max wait time for completion (default: 60000)
 */
async function clickTaskButton(page, id, options = {}) {
    const { waitForComplete = true, timeout = 60000 } = options;

    await page.click(`#${id}`);

    if (waitForComplete) {
        // Task buttons add a 'running' class or disabled state while processing
        await page.waitForFunction(
            (btnId) => {
                const btn = document.getElementById(btnId);
                return btn && !btn.disabled && !btn.classList.contains('running');
            },
            id,
            { timeout }
        );
        await waitForReactivity(page);
    }
}

// ---- INPUTS -----------------------------------------------------------------

/**
 * Fill a text input.
 * @param {Page} page - Playwright page
 * @param {string} id - Input ID
 * @param {string} value - Text to enter
 * @param {Object} options
 * @param {boolean} options.clear - Clear existing text first (default: true)
 */
async function fillInput(page, id, value, options = {}) {
    const { clear = true } = options;
    const selector = `#${id}`;
    if (clear) {
        await page.fill(selector, '');
    }
    await page.fill(selector, value);
}

/**
 * Fill a numeric input.
 * @param {Page} page - Playwright page
 * @param {string} id - Input ID
 * @param {number} value - Number to enter
 */
async function fillNumericInput(page, id, value) {
    await fillInput(page, id, String(value));
}

// ---- DROPDOWNS --------------------------------------------------------------

/**
 * Select an option from a selectInput/selectizeInput.
 * @param {Page} page - Playwright page
 * @param {string} id - Select element ID
 * @param {string} value - Option value to select
 * @param {Object} options
 * @param {boolean} options.waitForReactivity - Wait after selection (default: true)
 */
async function selectDropdown(page, id, value, options = {}) {
    const { waitForReactivity: doWait = true } = options;

    // Check if it's a selectize input (has sibling .selectize-control)
    const isSelectize = await page.$(`#${id} + .selectize-control`);

    if (isSelectize) {
        // For selectize: click control, then click option
        await page.click(`#${id} + .selectize-control .selectize-input`);
        await page.click(`.selectize-dropdown [data-value="${value}"]`);
    } else {
        // Standard select
        await page.selectOption(`#${id}`, value);
    }

    if (doWait) {
        await waitForReactivity(page);
    }
}

/**
 * Get current value of a select input.
 * @param {Page} page - Playwright page
 * @param {string} id - Select element ID
 * @returns {Promise<string>}
 */
async function getDropdownValue(page, id) {
    return page.inputValue(`#${id}`);
}

/**
 * Get all available options from a select input.
 * @param {Page} page - Playwright page
 * @param {string} id - Select element ID
 * @returns {Promise<Array<{value: string, text: string}>>}
 */
async function getDropdownOptions(page, id) {
    return page.evaluate((selectId) => {
        const select = document.getElementById(selectId);
        if (!select) return [];
        return Array.from(select.options).map(opt => ({
            value: opt.value,
            text: opt.text
        }));
    }, id);
}

// ---- CHECKBOXES/RADIOS ------------------------------------------------------

/**
 * Check or uncheck a checkbox input.
 * @param {Page} page - Playwright page
 * @param {string} id - Checkbox ID
 * @param {boolean} checked - Desired state (default: true)
 */
async function setCheckbox(page, id, checked = true) {
    const selector = `#${id}`;
    const currentState = await page.isChecked(selector);
    if (currentState !== checked) {
        await page.click(selector);
        await waitForReactivity(page);
    }
}

/**
 * Select a radio button option.
 * @param {Page} page - Playwright page
 * @param {string} groupId - Radio group container ID
 * @param {string} value - Value of option to select
 */
async function selectRadio(page, groupId, value) {
    await page.click(`#${groupId} input[value="${value}"]`);
    await waitForReactivity(page);
}

// ---- SLIDERS ----------------------------------------------------------------

/**
 * Set a slider input value.
 * @param {Page} page - Playwright page
 * @param {string} id - Slider input ID
 * @param {number} value - Value to set
 */
async function setSlider(page, id, value) {
    // Shiny sliders use ionRangeSlider - set via Shiny.setInputValue
    await page.evaluate(
        ({ id, val }) => Shiny.setInputValue(id, val, { priority: 'event' }),
        { id, val: value }
    );
    await waitForReactivity(page);
}

// ---- MODALS -----------------------------------------------------------------

/**
 * Close the currently open modal.
 * @param {Page} page - Playwright page
 * @param {Object} options
 * @param {string} options.method - 'button' (click X) or 'backdrop' (click outside) or 'escape'
 */
async function closeModal(page, options = {}) {
    const { method = 'button' } = options;

    switch (method) {
        case 'button':
            await page.click('.modal.show .btn-close, .modal.show [data-bs-dismiss="modal"]');
            break;
        case 'backdrop':
            await page.click('.modal.show', { position: { x: 10, y: 10 } });
            break;
        case 'escape':
            await page.keyboard.press('Escape');
            break;
    }

    await page.waitForSelector('.modal.show', { state: 'hidden' });
}

/**
 * Click a button inside a modal.
 * @param {Page} page - Playwright page
 * @param {string} buttonText - Button text to match
 */
async function clickModalButton(page, buttonText) {
    await page.click(`.modal.show button:has-text("${buttonText}")`);
    await waitForReactivity(page);
}

// ---- SIDEBAR ----------------------------------------------------------------

/**
 * Check if sidebar is open.
 * @param {Page} page - Playwright page
 * @returns {Promise<boolean>}
 */
async function isSidebarOpen(page) {
    const sidebar = await page.$('.bslib-sidebar-layout');
    if (!sidebar) return false;
    return page.evaluate(el => !el.classList.contains('sidebar-collapsed'), sidebar);
}

/**
 * Toggle sidebar open/closed.
 * @param {Page} page - Playwright page
 */
async function toggleSidebar(page) {
    await page.click('.bslib-sidebar-layout .collapse-toggle');
    await waitForReactivity(page);
}

// ---- CARDS ------------------------------------------------------------------

/**
 * Expand a collapsed bslib card.
 * @param {Page} page - Playwright page
 * @param {string} id - Card element ID
 */
async function expandCard(page, id) {
    const card = await page.$(`#${id}`);
    const isCollapsed = await page.evaluate(el => el.classList.contains('collapsed'), card);
    if (isCollapsed) {
        await page.click(`#${id} .bslib-full-screen-enter, #${id} [data-bs-toggle="collapse"]`);
        await waitForReactivity(page);
    }
}

// ---- TABLES -----------------------------------------------------------------

/**
 * Click a row in a DT datatable.
 * @param {Page} page - Playwright page
 * @param {string} tableId - DataTable output ID
 * @param {number} rowIndex - Row index (0-based)
 */
async function clickTableRow(page, tableId, rowIndex) {
    await page.click(`#${tableId} tbody tr:nth-child(${rowIndex + 1})`);
    await waitForReactivity(page);
}

/**
 * Get table cell text.
 * @param {Page} page - Playwright page
 * @param {string} tableId - Table ID
 * @param {number} rowIndex - Row index (0-based)
 * @param {number} colIndex - Column index (0-based)
 * @returns {Promise<string>}
 */
async function getTableCell(page, tableId, rowIndex, colIndex) {
    return page.textContent(
        `#${tableId} tbody tr:nth-child(${rowIndex + 1}) td:nth-child(${colIndex + 1})`
    );
}

// ---- FILES ------------------------------------------------------------------

/**
 * Upload a file to a Shiny fileInput.
 * @param {Page} page - Playwright page
 * @param {string} id - File input ID (without #)
 * @param {string} filepath - Absolute path to file
 * @param {Object} options
 * @param {boolean} options.waitForCompleted - Wait for upload bar to complete (default: true)
 */
async function uploadFile(page, id, filepath, options = {}) {
    const { waitForCompleted = true } = options;

    // Shiny fileInput id points directly to the input[type="file"]
    // However, sometimes it's wrapped. We try the ID directly first.
    // Note: Playwright can handle hidden file inputs.
    const selector = `#${id}`;

    await page.setInputFiles(selector, filepath);

    if (waitForCompleted) {
        // Wait for progress bar to finish (Shiny pattern)
        await page.waitForSelector(`#${id}_progress.progress-bar-success`, { timeout: 30000 }).catch(() => {
            // Sometimes it goes too fast to catch, so we check if file-name is shown
            // Shiny displays filenames in the text input part
        });
        await waitForReactivity(page);
    }
}

module.exports = {
    // Buttons
    clickButton,
    clickActionButton,
    clickTaskButton,
    // Inputs
    fillInput,
    fillNumericInput,
    // Dropdowns
    selectDropdown,
    getDropdownValue,
    getDropdownOptions,
    // Checkboxes/Radios
    setCheckbox,
    selectRadio,
    // Sliders
    setSlider,
    // Modals
    closeModal,
    clickModalButton,
    // Sidebar
    isSidebarOpen,
    toggleSidebar,
    // Cards
    expandCard,
    // Tables
    clickTableRow,
    getTableCell,
    // Files
    uploadFile
};
