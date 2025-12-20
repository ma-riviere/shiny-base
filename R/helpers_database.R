# ------ USER CRUD -------------------------------------------------------------

# Get or create user by auth0_sub. Returns user row (id, auth0_sub, created_at)
db_get_or_create_user <- function(pool, auth0_sub) {
    db_with_con(pool, \(con) {
        # Try to get existing user
        user <- DBI::dbGetQuery(
            con,
            glue::glue_sql("SELECT * FROM users WHERE auth0_sub = {auth0_sub}", .con = con)
        )

        if (nrow(user) > 0) {
            return(user[1, ])
        }

        # Create new user
        DBI::dbExecute(
            con,
            glue::glue_sql("INSERT INTO users (auth0_sub) VALUES ({auth0_sub})", .con = con)
        )

        # Return newly created user
        user <- DBI::dbGetQuery(
            con,
            glue::glue_sql("SELECT * FROM users WHERE auth0_sub = {auth0_sub}", .con = con)
        )
        return(user[1, ])
    })
}

# ------ DATASET CRUD ----------------------------------------------------------

# Get all datasets for a user (metadata only, no data column)
db_get_user_datasets <- function(pool, user_id) {
    datasets <- db_with_con(pool, \(con) {
        DBI::dbGetQuery(
            con,
            glue::glue_sql(
                "SELECT id, user_id, name, data, created_at
                 FROM datasets
                 WHERE user_id = {user_id}
                 ORDER BY created_at DESC",
                .con = con
            )
        )
    })

    if (purrr::is_empty(datasets) || nrow(datasets) == 0) {
        return(datasets)
    }

    # Calculate row_count and col_count from JSON data
    datasets$row_count <- vapply(
        datasets$data,
        \(json_str) {
            data_parsed <- yyjsonr::read_json_str(json_str)
            if (is.data.frame(data_parsed)) nrow(data_parsed) else length(data_parsed)
        },
        integer(1)
    )

    datasets$col_count <- vapply(
        datasets$data,
        \(json_str) {
            data_parsed <- yyjsonr::read_json_str(json_str)
            if (is.data.frame(data_parsed)) ncol(data_parsed) else 1L
        },
        integer(1)
    )

    # Remove data column before returning
    datasets$data <- NULL

    return(datasets)
}

# Get a single dataset with full data
db_get_dataset <- function(pool, dataset_id) {
    db_with_con(pool, \(con) {
        result <- DBI::dbGetQuery(
            con,
            glue::glue_sql("SELECT * FROM datasets WHERE id = {dataset_id}", .con = con)
        )
        if (nrow(result) == 0) {
            return(NULL)
        }
        return(result[1, ])
    })
}

# Create a new dataset. Returns the new dataset ID.
db_create_dataset <- function(pool, user_id, name, data_df) {
    data_json <- yyjsonr::write_json_str(data_df)

    db_with_con(pool, \(con) {
        DBI::dbExecute(
            con,
            glue::glue_sql(
                "INSERT INTO datasets (user_id, name, data)
                 VALUES ({user_id}, {name}, {data_json})",
                .con = con
            )
        )

        # Get the inserted ID
        result <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")
        return(result$id)
    })
}

# Delete a dataset by ID
db_delete_dataset <- function(pool, dataset_id) {
    db_with_con(pool, \(con) {
        DBI::dbExecute(
            con,
            glue::glue_sql("DELETE FROM datasets WHERE id = {dataset_id}", .con = con)
        )
    })
}

# Parse dataset JSON data back to data frame
db_parse_dataset_data <- function(data_json) {
    yyjsonr::read_json_str(data_json)
}

# ------ BOOKMARK CRUD ---------------------------------------------------------

# Register a new bookmark for a user.
# Deletes any previous bookmarks for this user (keeps only most recent).
# Returns the state_ids of deleted bookmarks for filesystem cleanup.
db_register_bookmark <- function(pool, user_id, state_id) {
    db_with_con(pool, \(con) {
        # Get existing bookmarks to delete from filesystem
        old_bookmarks <- DBI::dbGetQuery(
            con,
            glue::glue_sql("SELECT state_id FROM bookmarks WHERE user_id = {user_id}", .con = con)
        )

        # Delete old bookmarks from DB
        if (nrow(old_bookmarks) > 0) {
            DBI::dbExecute(
                con,
                glue::glue_sql("DELETE FROM bookmarks WHERE user_id = {user_id}", .con = con)
            )
        }

        # Insert new bookmark
        DBI::dbExecute(
            con,
            glue::glue_sql(
                "INSERT INTO bookmarks (user_id, state_id) VALUES ({user_id}, {state_id})",
                .con = con
            )
        )

        return(old_bookmarks$state_id)
    })
}

# Get all expired bookmarks (older than expiry_minutes).
# Returns data frame with state_id column.
db_get_expired_bookmarks <- function(pool, expiry_minutes = 30) {
    db_with_con(pool, \(con) {
        # Use datetime function for SQLite, interval for PostgreSQL
        if (inherits(con, "SQLiteConnection")) {
            DBI::dbGetQuery(
                con,
                glue::glue_sql(
                    "SELECT state_id FROM bookmarks
                     WHERE created_at < datetime('now', {paste0('-', expiry_minutes, ' minutes')})",
                    .con = con
                )
            )
        } else {
            DBI::dbGetQuery(
                con,
                glue::glue_sql(
                    "SELECT state_id FROM bookmarks
                     WHERE created_at < NOW() - INTERVAL '{expiry_minutes} minutes'",
                    .con = con
                )
            )
        }
    })
}

# Delete bookmarks by state_ids from DB.
db_delete_bookmarks <- function(pool, state_ids) {
    if (length(state_ids) == 0) {
        return(invisible(NULL))
    }
    db_with_con(pool, \(con) {
        DBI::dbExecute(
            con,
            glue::glue_sql("DELETE FROM bookmarks WHERE state_id IN ({state_ids*})", .con = con)
        )
    })
}

# Get all bookmarks from DB (for orphan cleanup).
db_get_all_bookmarks <- function(pool) {
    db_with_con(pool, \(con) {
        DBI::dbGetQuery(con, "SELECT state_id FROM bookmarks")
    })
}

# Get the user's most recent bookmark if it's within max_age_minutes.
# Returns NULL if no recent bookmark exists.
db_get_user_recent_bookmark <- function(pool, user_id, max_age_minutes = 30) {
    db_with_con(pool, \(con) {
        if (inherits(con, "SQLiteConnection")) {
            result <- DBI::dbGetQuery(
                con,
                glue::glue_sql(
                    "SELECT state_id, created_at FROM bookmarks
                     WHERE user_id = {user_id}
                       AND created_at > datetime('now', {paste0('-', max_age_minutes, ' minutes')})
                     ORDER BY created_at DESC
                     LIMIT 1",
                    .con = con
                )
            )
        } else {
            result <- DBI::dbGetQuery(
                con,
                glue::glue_sql(
                    "SELECT state_id, created_at FROM bookmarks
                     WHERE user_id = {user_id}
                       AND created_at > NOW() - INTERVAL '{max_age_minutes} minutes'
                     ORDER BY created_at DESC
                     LIMIT 1",
                    .con = con
                )
            )
        }
        if (nrow(result) == 0) {
            return(NULL)
        }
        return(result[1, ])
    })
}
