-- App-private base schema: sessions, bookmarks (lands in the app schema).
-- users/datasets/models live in the cross-app "shared" schema (schema-shared.sql).
-- FKs to shared.users are schema-qualified on purpose: unqualified resolution
-- at DDL time could bind to a leftover app-local users table.
-- PostgreSQL version

-- Sessions table
-- Tracks active and historical user sessions for admin dashboard
CREATE TABLE IF NOT EXISTS sessions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_token VARCHAR(64) NOT NULL UNIQUE,
    user_id BIGINT,
    auth0_sub VARCHAR(255),
    started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMPTZ,
    end_reason VARCHAR(20),
    FOREIGN KEY (user_id) REFERENCES shared.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_ended_at ON sessions(ended_at);
CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at);

-- Bookmarks table
-- Tracks server-side bookmarks per user for cleanup
CREATE TABLE IF NOT EXISTS bookmarks (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    state_id VARCHAR(64) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES shared.users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_id ON bookmarks(user_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_created_at ON bookmarks(created_at);
