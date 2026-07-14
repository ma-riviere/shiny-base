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
    # Dimensions are persisted (n_rows/n_cols, kept by every writer of the
    # shared datasets table), so the data blob is never fetched or parsed here.
    query <- dplyr::tbl(db_pool, "datasets") |>
        dplyr::filter(user_id == !!user_id) |>
        dplyr::select(id, user_id, name, row_count = n_rows, col_count = n_cols, created_at, updated_at) |>
        dplyr::arrange(dplyr::desc(created_at))

    # Apply pagination if specified
    if (!is.null(limit)) {
        query <- query |>
            utils::head(limit + offset) |>
            utils::tail(limit)
    }

    return(dplyr::collect(query))
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

# Get a single dataset with full data (scoped to the owning user - prevents IDOR)
db_get_dataset <- function(dataset_id, user_id) {
    result <- dplyr::tbl(db_pool, "datasets") |>
        dplyr::filter(id == !!dataset_id, user_id == !!user_id) |>
        dplyr::collect()
    if (nrow(result) == 0) {
        return(NULL)
    }
    return(result[1, ])
}

# yyjsonr drops data.frame rownames on write (jsonlite emitted them as a "_row"
# string field per row object and restores it on parse). Keep meaningful
# rownames through the same jsonlite-compatible field: injected into the
# serialized rows ONLY - never listed in `columns`, never counted in n_cols -
# and restored to real rownames on read. Numeric-looking rownames (subset
# leftovers like "3", "5") are noise and are not persisted.
# SYNC CONTRACT: mirrored in plumber2-base back/R/datasets.R (shared datasets).
inject_rownames <- function(df) {
    if (.row_names_info(df) <= 0L) {
        return(df)
    }
    if (!is.character(utils::type.convert(rownames(df), as.is = TRUE))) {
        return(df)
    }
    df[["_row"]] <- rownames(df)
    rownames(df) <- NULL
    return(df)
}

restore_rownames <- function(df) {
    if (is.data.frame(df) && "_row" %in% names(df)) {
        rownames(df) <- df[["_row"]]
        df[["_row"]] <- NULL
    }
    return(df)
}

# Create a new dataset. Returns number of rows affected (1 on success).
db_create_dataset <- function(user_id, name, data_df, description = NULL) {
    # {columns, rows} envelope (parity with plumber2-base, which reads the same
    # shared table): jsonb normalizes OBJECT key order, so the column order
    # must ride in an array, which jsonb preserves. Rownames ride inside the
    # row objects as "_row" (inject_rownames above).
    data_json <- yyjsonr::write_json_str(list(columns = names(data_df), rows = inject_rownames(data_df)))

    db_execute(
        "INSERT INTO datasets (user_id, name, description, data, n_rows, n_cols)
         VALUES ({user_id}, {name}, {description}, {data_json}, {n_rows}, {n_cols})",
        user_id = user_id,
        name = name,
        description = description %||% NA_character_,
        data_json = data_json,
        n_rows = nrow(data_df),
        n_cols = ncol(data_df),
        pool = db_pool
    )
}

# Update a dataset name by ID (scoped to the owning user - prevents IDOR)
db_update_dataset_name <- function(dataset_id, new_name, user_id) {
    db_execute(
        "UPDATE datasets SET name = {new_name} WHERE id = {dataset_id} AND user_id = {user_id}",
        dataset_id = dataset_id,
        new_name = new_name,
        user_id = user_id
    )
}

# Delete a dataset by ID (also deletes linked models; scoped to the owning user - prevents IDOR)
db_delete_dataset <- function(dataset_id, user_id) {
    # Delete linked models first (manual cascade - SQLite PRAGMA foreign_keys doesn't persist across pool connections)
    db_execute(
        "DELETE FROM models WHERE dataset_id = {dataset_id} AND user_id = {user_id}",
        dataset_id = dataset_id,
        user_id = user_id
    )
    db_execute(
        "DELETE FROM datasets WHERE id = {dataset_id} AND user_id = {user_id}",
        dataset_id = dataset_id,
        user_id = user_id
    )
}

# Parse dataset JSON data back to a data frame, restoring column order from the
# {columns, rows} envelope. Wrapped-shape check first: yyjsonr promotes the
# wrapper object itself to a data.frame whose $rows holds the real data.
db_parse_dataset_data <- function(data_json) {
    parsed <- yyjsonr::read_json_str(data_json)
    if (!is.null(parsed$columns) && !is.null(parsed$rows)) {
        df <- restore_rownames(as.data.frame(parsed$rows))
        return(df[, unlist(parsed$columns, use.names = FALSE), drop = FALSE])
    }
    return(parsed)
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

# Get a single model with full blob (scoped to the owning user - prevents IDOR)
#
# @param model_id Model ID
# @param user_id User ID (authoritative owner filter)
# @return Single row data frame or NULL if not found
db_get_model <- function(model_id, user_id) {
    result <- dplyr::tbl(db_pool, "models") |>
        dplyr::filter(id == !!model_id, user_id == !!user_id) |>
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
# @param metrics Named list of fit metrics (stored as JSON, parity with plumber2-base)
# @return Model ID (new or existing)
db_upsert_model <- function(user_id, dataset_id, formula, model_obj, metrics) {
    # Verify the dataset belongs to this user before attaching a model to it.
    # dataset_id comes from client-settable shared UI state, so this closes the
    # write-side IDOR (a user saving a model against another user's dataset).
    owns <- db_query(
        "SELECT 1 AS ok FROM datasets WHERE id = {dataset_id} AND user_id = {user_id}",
        dataset_id = dataset_id,
        user_id = user_id
    )
    if (nrow(owns) == 0) {
        cli::cli_abort("Dataset does not belong to the current user.")
    }

    # Normalize formula (trim + collapse whitespace)
    formula_clean <- gsub("\\s+", " ", trimws(formula))

    # Serialize model to raw bytes
    model_blob <- serialize(model_obj, NULL)
    metrics_json <- yyjsonr::write_json_str(metrics, auto_unbox = TRUE)

    # Atomic upsert: the models table is shared with plumber2-base, so a
    # check-then-insert would race with a concurrent writer. ON CONFLICT +
    # RETURNING work on both PostgreSQL and SQLite (>= 3.35).
    result <- db_query(
        "INSERT INTO models (user_id, dataset_id, formula, metrics, model_blob)
         VALUES ({user_id}, {dataset_id}, {formula}, {metrics_json}, {model_blob})
         ON CONFLICT (user_id, dataset_id, formula)
         DO UPDATE SET metrics = EXCLUDED.metrics, model_blob = EXCLUDED.model_blob,
                       updated_at = CURRENT_TIMESTAMP
         RETURNING id",
        user_id = user_id,
        dataset_id = dataset_id,
        formula = formula_clean,
        metrics_json = metrics_json,
        model_blob = model_blob
    )
    return(result$id[1])
}

# Delete a model by ID (scoped to the owning user - prevents IDOR)
db_delete_model <- function(model_id, user_id) {
    db_execute(
        "DELETE FROM models WHERE id = {model_id} AND user_id = {user_id}",
        model_id = model_id,
        user_id = user_id
    )
}

# Deserialize model blob back to R object.
# Trust boundary: unserialize() of attacker-controlled bytes can execute code via
# S4/refclass dispatch. models.model_blob now lives in the shared schema with TWO
# writers (this app and plumber2-base) — both same-owner, same trust domain, and
# db_get_model() stays user-scoped, so this remains an accepted risk. If any less
# trusted writer ever gains access (import feature, third app), add an HMAC over
# the blob and verify it here before unserialize(). See SECURITY.md P3-4.
db_unserialize_model <- function(model_blob) {
    unserialize(model_blob)
}
