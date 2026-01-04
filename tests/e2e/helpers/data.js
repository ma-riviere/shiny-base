/**
 * Data generation helpers for E2E tests.
 */
const fs = require('fs');
const path = require('path');

const TOY_DATASETS = {
    mtcars: "mpg,wt\n21,2.620\n21,2.875\n22.8,2.320\n21.4,3.215\n18.7,3.440\n18.1,3.460"
};

/**
 * Ensure the e2e temp directory exists.
 */
function ensureTempDir() {
    const tempDir = path.resolve(__dirname, '../temp_data');
    if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
    }
    return tempDir;
}

/**
 * Create a toy CSV file.
 * @param {string} name - Name of the file (without extension)
 * @param {string} key - Key of the dataset to use (default: mtcars)
 * @returns {string} - Absolute path to the created file
 */
function createToyDataset(name, key = 'mtcars') {
    const tempDir = ensureTempDir();
    const filePath = path.join(tempDir, `${name}.csv`);

    const content = TOY_DATASETS[key];
    if (!content) throw new Error(`Unknown dataset key: ${key}`);

    fs.writeFileSync(filePath, content);
    return filePath;
}

/**
 * Remove a file if it exists.
 * @param {string} filePath 
 */
function deleteFile(filePath) {
    if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
    }
}

module.exports = { createToyDataset, deleteFile, TOY_DATASETS };
