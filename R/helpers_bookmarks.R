# Bookmark cleanup helpers
#
# Manages server-side bookmark lifecycle:
# - Only keep the most recent bookmark per user
# - Delete bookmarks older than expiry time
# - Clean orphaned bookmark folders (not in DB)
#
# Config constants (BOOKMARK_DIR, BOOKMARK_EXPIRY_MINUTES) are defined in global.R

# Delete bookmark folder from filesystem
delete_bookmark_folder <- function(state_id) {
    folder_path <- file.path(BOOKMARK_DIR, state_id)
    if (dir.exists(folder_path)) {
        unlink(folder_path, recursive = TRUE)
        # cat("[bookmarks] Deleted folder:", state_id, "\n", file = stderr())
    }
}

# Delete multiple bookmark folders
delete_bookmark_folders <- function(state_ids) {
    for (state_id in state_ids) {
        delete_bookmark_folder(state_id)
    }
}

# Run bookmark cleanup: expired + orphaned folders.
# Should be called on app startup.
bookmark_cleanup <- function(pool) {
    if (!dir.exists(BOOKMARK_DIR)) {
        return(invisible(NULL))
    }

    # 1. Delete expired bookmarks
    expired <- db_get_expired_bookmarks(pool, BOOKMARK_EXPIRY_MINUTES)
    if (nrow(expired) > 0) {
        delete_bookmark_folders(expired$state_id)
        db_delete_bookmarks(pool, expired$state_id)
        cat("[bookmarks] Cleaned", nrow(expired), "expired bookmarks\n", file = stderr())
    }

    # 2. Delete orphaned folders (exist on disk but not in DB)
    db_bookmarks <- db_get_all_bookmarks(pool)
    disk_folders <- list.dirs(BOOKMARK_DIR, full.names = FALSE, recursive = FALSE)

    orphans <- setdiff(disk_folders, db_bookmarks$state_id)
    if (length(orphans) > 0) {
        delete_bookmark_folders(orphans)
        cat("[bookmarks] Cleaned", length(orphans), "orphaned folders\n", file = stderr())
    }
}

# Manually save bookmark state on session disconnect.
# Called from onSessionEnded callback (no reactive context available).
# Returns the state_id if successful, NULL otherwise.
# Wrapped in tryCatch to handle app shutdown race conditions gracefully.
save_bookmark_on_disconnect <- function(pool, session, input) {
    tryCatch(
        save_bookmark_on_disconnect_impl(pool, session, input),
        error = \(e) {
            # Silently ignore errors during app shutdown (pool closed)
            NULL
        }
    )
}

save_bookmark_on_disconnect_impl <- function(pool, session, input) {
    auth0_sub <- purrr::pluck(session$userData$auth0_info, "sub")
    if (purrr::is_empty(auth0_sub)) {
        cat("[bookmarks] onSessionEnded: No auth0_sub, skipping\n", file = stderr())
        return(NULL)
    }

    # Generate unique state ID (alphanumeric only - Shiny rejects hyphens/special chars)
    state_id <- paste0(
        format(Sys.time(), "%Y%m%d%H%M%S"),
        substr(session$token, 1, 8)
    )

    # Create bookmark directory
    bookmark_path <- file.path(BOOKMARK_DIR, state_id)
    if (!dir.exists(bookmark_path)) {
        dir.create(bookmark_path, recursive = TRUE)
    }

    # Capture input state (isolate because no reactive context)
    input_state <- isolate(reactiveValuesToList(input))

    # Remove excluded inputs (same as setBookmarkExclude)
    excluded <- c("._auth0logout_", "sidebar-toggle")
    input_state <- input_state[!names(input_state) %in% excluded]

    # Save to input.rds (same format as Shiny's native bookmarking)
    tryCatch(
        {
            saveRDS(input_state, file = file.path(bookmark_path, "input.rds"))
        },
        error = \(e) {
            cat("[bookmarks] onSessionEnded: Failed to save input.rds:", e$message, "\n", file = stderr())
            return(NULL)
        }
    )

    # Register in DB WITHOUT deleting old bookmarks.
    # Unlike explicit bookmark saves, disconnect saves should not delete previous bookmarks
    # because the user might be trying to restore that exact bookmark on reconnect.
    # Old bookmarks will be cleaned up by periodic cleanup (bookmark_cleanup in global.R).
    user <- db_get_or_create_user(pool, auth0_sub)
    db_with_con(pool, \(con) {
        DBI::dbExecute(
            con,
            glue::glue_sql(
                "INSERT INTO bookmarks (user_id, state_id) VALUES ({user$id}, {state_id})",
                .con = con
            )
        )
    })

    cat("[bookmarks] onSessionEnded: Saved bookmark", state_id, "for user", user$id, "\n", file = stderr())
    return(state_id)
}

# Register bookmark and cleanup previous ones for this user.
# Called from onBookmark callback.
register_user_bookmark <- function(pool, user_id, state_id) {
    old_state_ids <- db_register_bookmark(pool, user_id, state_id)
    delete_bookmark_folders(old_state_ids)

    if (length(old_state_ids) > 0) {
        cat(
            "[bookmarks] User",
            user_id,
            "- replaced",
            length(old_state_ids),
            "old bookmark(s) with",
            state_id,
            "\n",
            file = stderr()
        )
    } else {
        cat("[bookmarks] User", user_id, "- created bookmark", state_id, "\n", file = stderr())
    }
}
