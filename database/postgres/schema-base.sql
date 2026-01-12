-- Base schema for Shiny apps with Auth0 authentication
-- Contains: users, sessions, bookmarks tables
-- PostgreSQL version

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    auth0_sub VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_users_auth0_sub ON users(auth0_sub);

-- Sessions table
-- Tracks active and historical user sessions for admin dashboard
CREATE TABLE IF NOT EXISTS sessions (
    id SERIAL PRIMARY KEY,
    session_token VARCHAR(64) NOT NULL UNIQUE,
    user_id INTEGER,
    auth0_sub VARCHAR(255),
    started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMPTZ,
    end_reason VARCHAR(20),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_ended_at ON sessions(ended_at);
CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at);

-- Bookmarks table
-- Tracks server-side bookmarks per user for cleanup
CREATE TABLE IF NOT EXISTS bookmarks (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    state_id VARCHAR(64) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_id ON bookmarks(user_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_created_at ON bookmarks(created_at);
