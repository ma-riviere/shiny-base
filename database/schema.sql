-- App-specific schema for shiny-base
-- Base tables (users, sessions, bookmarks) are in R/shiny-utils/schema-base.sql

-- Datasets table
-- Stores uploaded datasets as JSON
-- PostgreSQL uses JSONB, SQLite uses TEXT
CREATE TABLE IF NOT EXISTS datasets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    data TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_datasets_user_id ON datasets(user_id);
-- Note: updated_at is managed by the application layer, not a trigger,
-- because the schema is executed via split-by-semicolon which breaks trigger syntax.
