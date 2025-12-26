# ------ USER CRUD -------------------------------------------------------------

# Get or create user by auth0_sub. Returns user row (id, auth0_sub, created_at)
db_get_or_create_user <- function(auth0_sub) {
    # Try to get existing user
    user <- dplyr::tbl(db_pool, "users") |>
        dplyr::filter(auth0_sub == !!auth0_sub) |>
        dplyr::collect()

    if (nrow(user) > 0) {
        return(user[1, ])
    }

    # Create new user
    db_execute("INSERT INTO users (auth0_sub) VALUES ({auth0_sub})", auth0_sub = auth0_sub)

    # Return newly created user
    user <- dplyr::tbl(db_pool, "users") |>
        dplyr::filter(auth0_sub == !!auth0_sub) |>
        dplyr::collect()
    return(user[1, ])
}

# Get or create a temporary user (for when Auth0 is disabled).
# Uses session token to generate a consistent temp ID per session.
# Returns user row (id, auth0_sub, created_at)
#
# @param session_token Unique session identifier (e.g. from session$token)
db_get_or_create_temp_user <- function(session_token) {
    # Use first 8 chars of session token hash as temporary user ID
    temp_id <- paste0("tmp_", substr(digest::digest(session_token, algo = "md5"), 1, 12))
    db_get_or_create_user(temp_id)
}

# ------ DATASET CRUD ----------------------------------------------------------

# Get all datasets for a user (metadata only, no data column)
# Supports pagination with limit and offset parameters.
#
# @param user_id User ID to filter by
# @param limit Maximum number of records to return (default: NULL = all)
# @param offset Number of records to skip (default: 0)
# @return Data frame with dataset metadata (id, user_id, name, row_count, col_count, created_at, updated_at)
db_get_user_datasets <- function(user_id, limit = NULL, offset = 0) {
    # Build query with dbplyr
    query <- dplyr::tbl(db_pool, "datasets") |>
        dplyr::filter(user_id == !!user_id) |>
        dplyr::select(id, user_id, name, data, created_at, updated_at) |>
        dplyr::arrange(dplyr::desc(created_at))

    # Apply pagination if specified
    if (!is.null(limit)) {
        query <- query |>
            utils::head(limit + offset) |>
            utils::tail(limit)
    }

    datasets <- dplyr::collect(query)

    if (purrr::is_empty(datasets) || nrow(datasets) == 0) {
        return(datasets)
    }

    # Calculate row_count and col_count from JSON data (single parse per dataset)
    stats <- vapply(
        datasets$data,
        \(json_str) {
            data_parsed <- yyjsonr::read_json_str(json_str)
            if (is.data.frame(data_parsed)) {
                c(row = nrow(data_parsed), col = ncol(data_parsed))
            } else {
                c(row = length(data_parsed), col = 1L)
            }
        },
        integer(2)
    )

    datasets$row_count <- stats["row", ]
    datasets$col_count <- stats["col", ]

    # Remove data column before returning
    datasets$data <- NULL

    return(datasets)
}

# Get total count of datasets for a user (for pagination)
#
# @param user_id User ID to filter by
# @return Integer count
db_get_user_datasets_count <- function(user_id) {
    result <- dplyr::tbl(db_pool, "datasets") |>
        dplyr::filter(user_id == !!user_id) |>
        dplyr::summarise(count = dplyr::n()) |>
        dplyr::collect()
    as.integer(result$count)
}

# Get a single dataset with full data
db_get_dataset <- function(dataset_id) {
    result <- dplyr::tbl(db_pool, "datasets") |>
        dplyr::filter(id == !!dataset_id) |>
        dplyr::collect()
    if (nrow(result) == 0) {
        return(NULL)
    }
    return(result[1, ])
}

# Create a new dataset. Returns the new dataset ID.
# Note: Requires db_with_con because we need the same connection for INSERT + get-last-ID.
db_create_dataset <- function(user_id, name, data_df) {
    data_json <- yyjsonr::write_json_str(data_df)

    db_with_con(db_pool, \(con) {
        sql <- glue::glue_sql(
            "INSERT INTO datasets (user_id, name, data) VALUES ({user_id}, {name}, {data_json})",
            .con = con
        )
        DBI::dbExecute(con, sql)

        # Get the inserted ID (SQLite-specific; PostgreSQL would use RETURNING clause)
        DBI::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id
    })
}

# Update a dataset name by ID
db_update_dataset_name <- function(dataset_id, new_name) {
    db_execute(
        "UPDATE datasets SET name = {new_name} WHERE id = {dataset_id}",
        dataset_id = dataset_id,
        new_name = new_name
    )
}

# Delete a dataset by ID
db_delete_dataset <- function(dataset_id) {
    db_execute("DELETE FROM datasets WHERE id = {dataset_id}", dataset_id = dataset_id)
}

# Parse dataset JSON data back to data frame
db_parse_dataset_data <- function(data_json) {
    yyjsonr::read_json_str(data_json)
}

# ------ BOOKMARK CRUD ---------------------------------------------------------

# Register a new bookmark for a user.
# Deletes any previous bookmarks for this user (keeps only most recent).
# Returns the state_ids of deleted bookmarks for filesystem cleanup.
db_register_bookmark <- function(user_id, state_id) {
    # Get existing bookmarks to delete from filesystem
    old_bookmarks <- dplyr::tbl(db_pool, "bookmarks") |>
        dplyr::filter(user_id == !!user_id) |>
        dplyr::select(state_id) |>
        dplyr::collect()

    # Delete old bookmarks from DB
    if (nrow(old_bookmarks) > 0) {
        db_execute("DELETE FROM bookmarks WHERE user_id = {user_id}", user_id = user_id)
    }

    # Insert new bookmark
    db_execute(
        "INSERT INTO bookmarks (user_id, state_id) VALUES ({user_id}, {state_id})",
        user_id = user_id,
        state_id = state_id
    )

    return(old_bookmarks$state_id)
}

# Get all expired bookmarks (older than expiry_minutes).
# Returns data frame with state_id column.
db_get_expired_bookmarks <- function(expiry_minutes = 30) {
    # Calculate cutoff time in R, formatted for SQL comparison
    cutoff <- db_sql_datetime(lubridate::now() - lubridate::minutes(expiry_minutes))

    dplyr::tbl(db_pool, "bookmarks") |>
        dplyr::filter(created_at < !!cutoff) |>
        dplyr::select(state_id) |>
        dplyr::collect()
}

# Delete bookmarks by state_ids from DB.
db_delete_bookmarks <- function(state_ids) {
    if (length(state_ids) == 0) {
        return(invisible(NULL))
    }
    db_execute("DELETE FROM bookmarks WHERE state_id IN ({state_ids*})", state_ids = state_ids)
}

# Get all bookmarks from DB (for orphan cleanup).
db_get_all_bookmarks <- function() {
    dplyr::tbl(db_pool, "bookmarks") |>
        dplyr::select(state_id) |>
        dplyr::collect()
}

# Get the user's most recent bookmark if it's within max_age_minutes.
# Returns NULL if no recent bookmark exists.
db_get_user_recent_bookmark <- function(user_id, max_age_minutes = 30) {
    # Calculate cutoff time in R, formatted for SQL comparison
    cutoff <- db_sql_datetime(lubridate::now() - lubridate::minutes(max_age_minutes))

    result <- dplyr::tbl(db_pool, "bookmarks") |>
        dplyr::filter(user_id == !!user_id, created_at > !!cutoff) |>
        dplyr::select(state_id, created_at) |>
        dplyr::arrange(dplyr::desc(created_at)) |>
        utils::head(1) |>
        dplyr::collect()

    if (nrow(result) == 0) {
        return(NULL)
    }
    return(result[1, ])
}
