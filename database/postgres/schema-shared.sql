-- Shared cross-app tables (schema "shared"): users, datasets, models.
-- SYNC CONTRACT: this file must stay byte-identical with plumber2-base's
-- db/schema-shared.sql. Both apps apply it idempotently at container start
-- (advisory lock hashtext('shared_ddl'), SET LOCAL ROLE shared, SET LOCAL
-- search_path TO shared). Schema changes are appended as idempotent
-- statements (ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS, ...)
-- in BOTH repos, plus the expected-columns check in each applier.
-- No statement may contain a semicolon inside it (split-by-semicolon applier).

CREATE TABLE IF NOT EXISTS users (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    auth0_sub    text UNIQUE,
    email        text,
    nickname     text,
    is_guest     boolean NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz
);

CREATE TABLE IF NOT EXISTS datasets (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name        text NOT NULL,
    description text,
    data        jsonb NOT NULL,
    n_rows      integer NOT NULL,
    n_cols      integer NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS datasets_user_id_idx ON datasets (user_id);

CREATE INDEX IF NOT EXISTS datasets_user_id_created_at_idx ON datasets (user_id, created_at);

CREATE TABLE IF NOT EXISTS models (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    dataset_id bigint NOT NULL REFERENCES datasets (id) ON DELETE CASCADE,
    formula    text NOT NULL,
    metrics    jsonb NOT NULL,
    model_blob bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, dataset_id, formula)
);

CREATE INDEX IF NOT EXISTS models_user_id_idx ON models (user_id);

CREATE INDEX IF NOT EXISTS models_dataset_id_idx ON models (dataset_id);
