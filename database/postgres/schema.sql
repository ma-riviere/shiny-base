-- App-specific schema for shiny-base
-- Base tables (users, sessions, bookmarks) are in schema-base.sql
-- PostgreSQL version

-- Datasets table
-- Stores uploaded datasets as JSONB
CREATE TABLE IF NOT EXISTS datasets (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_datasets_user_id ON datasets(user_id);

-- Models table
-- Stores fitted models (butchered + serialized). Metrics are computed on display.
CREATE TABLE IF NOT EXISTS models (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    dataset_id INTEGER NOT NULL,
    formula TEXT NOT NULL,
    model_blob BYTEA,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (dataset_id) REFERENCES datasets(id) ON DELETE CASCADE,
    UNIQUE(user_id, dataset_id, formula)
);
CREATE INDEX IF NOT EXISTS idx_models_user_id ON models(user_id);
CREATE INDEX IF NOT EXISTS idx_models_dataset_id ON models(dataset_id);
