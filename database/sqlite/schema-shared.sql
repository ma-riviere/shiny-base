-- SQLite dev/test mirror of the cross-app shared tables (postgres/schema-shared.sql).
-- Single namespace: SQLite has no schemas, so these sit next to the app tables.
-- Keep columns in lockstep with the postgres version.

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    auth0_sub TEXT UNIQUE,
    email TEXT,
    nickname TEXT,
    is_guest BOOLEAN NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP,
    status TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS datasets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    data TEXT NOT NULL,
    n_rows INTEGER NOT NULL,
    n_cols INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS datasets_user_id_idx ON datasets (user_id);

CREATE INDEX IF NOT EXISTS datasets_user_id_created_at_idx ON datasets (user_id, created_at);

CREATE TABLE IF NOT EXISTS models (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    dataset_id INTEGER NOT NULL,
    formula TEXT NOT NULL,
    metrics TEXT NOT NULL,
    model_blob BLOB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (dataset_id) REFERENCES datasets(id) ON DELETE CASCADE,
    UNIQUE (user_id, dataset_id, formula)
);

CREATE INDEX IF NOT EXISTS models_user_id_idx ON models (user_id);

CREATE INDEX IF NOT EXISTS models_dataset_id_idx ON models (dataset_id);
