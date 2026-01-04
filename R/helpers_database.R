# Dataset CRUD operations
#
# App-specific database operations for the datasets table.
# Base operations (users, sessions, bookmarks) are in shinyutils package.

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
        # Ensure consistent columns even for empty results
        datasets$row_count <- integer(0)
        datasets$col_count <- integer(0)
        datasets$data <- NULL
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
        pool::dbExecute(con, sql)

        # Get the inserted ID (SQLite-specific; PostgreSQL would use RETURNING clause)
        pool::dbGetQuery(con, "SELECT last_insert_rowid() as id")$id
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

# Delete a dataset by ID (also deletes linked models)
db_delete_dataset <- function(dataset_id) {
    # Delete linked models first (manual cascade - SQLite PRAGMA foreign_keys doesn't persist across pool connections)
    db_execute("DELETE FROM models WHERE dataset_id = {dataset_id}", dataset_id = dataset_id)
    db_execute("DELETE FROM datasets WHERE id = {dataset_id}", dataset_id = dataset_id)
}

# Parse dataset JSON data back to data frame
db_parse_dataset_data <- function(data_json) {
    yyjsonr::read_json_str(data_json)
}

# ------ MODEL CRUD OPERATIONS ------------------------------------------------

# Get models for a specific dataset (metadata only, no blob)
#
# @param user_id User ID
# @param dataset_id Dataset ID
# @return Data frame with model metadata (id, formula, created_at, updated_at)
db_get_models_for_dataset <- function(user_id, dataset_id) {
    dplyr::tbl(db_pool, "models") |>
        dplyr::filter(user_id == !!user_id, dataset_id == !!dataset_id) |>
        dplyr::select(id, formula, created_at, updated_at) |>
        dplyr::arrange(dplyr::desc(updated_at)) |>
        dplyr::collect()
}

# Get a single model with full blob
#
# @param model_id Model ID
# @return Single row data frame or NULL if not found
db_get_model <- function(model_id) {
    result <- dplyr::tbl(db_pool, "models") |>
        dplyr::filter(id == !!model_id) |>
        dplyr::collect()
    if (nrow(result) == 0) {
        return(NULL)
    }
    return(result[1, ])
}

# Insert or update a model (upsert by user_id, dataset_id, formula)
#
# @param user_id User ID
# @param dataset_id Dataset ID
# @param formula Formula string (will be normalized)
# @param model_obj Fitted model object (will be serialized)
# @return Model ID (new or existing)
db_upsert_model <- function(user_id, dataset_id, formula, model_obj) {
    # Normalize formula (trim + collapse whitespace)
    formula_clean <- gsub("\\s+", " ", trimws(formula))

    # Serialize model to raw bytes
    model_blob <- serialize(model_obj, NULL)

    # Check if model exists
    existing <- db_query(
        "SELECT id FROM models WHERE user_id = {user_id} AND dataset_id = {dataset_id} AND formula = {formula}",
        user_id = user_id,
        dataset_id = dataset_id,
        formula = formula_clean
    )

    if (nrow(existing) > 0) {
        db_execute(
            "UPDATE models SET model_blob = {model_blob}, updated_at = CURRENT_TIMESTAMP WHERE id = {id}",
            model_blob = model_blob,
            id = existing$id[1]
        )
        return(existing$id[1])
    } else {
        db_execute(
            "INSERT INTO models (user_id, dataset_id, formula, model_blob)
             VALUES ({user_id}, {dataset_id}, {formula}, {model_blob})",
            user_id = user_id,
            dataset_id = dataset_id,
            formula = formula_clean,
            model_blob = model_blob
        )
        # Get last inserted ID by re-querying (portable across SQLite/PostgreSQL)
        result <- db_query(
            "SELECT id FROM models WHERE user_id = {user_id} AND dataset_id = {dataset_id}
             AND formula = {formula} ORDER BY id DESC LIMIT 1",
            user_id = user_id,
            dataset_id = dataset_id,
            formula = formula_clean
        )
        return(result$id[1])
    }
}

# Delete a model by ID
db_delete_model <- function(model_id) {
    db_execute("DELETE FROM models WHERE id = {model_id}", model_id = model_id)
}

# Deserialize model blob back to R object
db_unserialize_model <- function(model_blob) {
    unserialize(model_blob)
}
