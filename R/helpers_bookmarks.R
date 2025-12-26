# Bookmark cleanup helpers
#
# Manages server-side bookmark lifecycle:
# - Only keep the most recent bookmark per user
# - Delete bookmarks older than expiry time
# - Clean orphaned bookmark folders (not in DB)
#
# Config options (set in global.R):
# - bookmark_dir: Directory for bookmark storage (default: "shiny_bookmarks")
# - bookmark_expiry_minutes: Bookmark TTL in minutes (default: 30)

# Delete bookmark folder from filesystem
delete_bookmark_folder <- function(state_id) {
    bookmark_dir <- getOption("bookmark_dir", "shiny_bookmarks")
    folder_path <- file.path(bookmark_dir, state_id)
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
bookmark_cleanup <- function() {
    log_debug("[BOOKMARKS] Running scheduled cleanup")
    bookmark_dir <- getOption("bookmark_dir", "shiny_bookmarks")
    if (!dir.exists(bookmark_dir)) {
        return(invisible(NULL))
    }

    # 1. Delete expired bookmarks
    expiry_minutes <- getOption("bookmark_expiry_minutes", 30)
    expired <- db_get_expired_bookmarks(expiry_minutes)
    if (nrow(expired) > 0) {
        delete_bookmark_folders(expired$state_id)
        db_delete_bookmarks(expired$state_id)
        log_info("[BOOKMARKS] Cleaned {nrow(expired)} expired bookmarks")
    }

    # 2. Delete orphaned folders (exist on disk but not in DB)
    db_bookmarks <- db_get_all_bookmarks()
    disk_folders <- list.dirs(bookmark_dir, full.names = FALSE, recursive = FALSE)

    orphans <- setdiff(disk_folders, db_bookmarks$state_id)
    if (length(orphans) > 0) {
        delete_bookmark_folders(orphans)
        log_info("[BOOKMARKS] Cleaned {length(orphans)} orphaned folders")
    }
}

# Manually save bookmark state on session disconnect.
# Called from onSessionEnded callback (no reactive context available).
# Returns the state_id if successful, NULL otherwise.
# Wrapped in tryCatch to handle app shutdown race conditions gracefully.
save_bookmark_on_disconnect <- function(session, input) {
    tryCatch(
        save_bookmark_on_disconnect_impl(session, input),
        error = \(e) {
            # Silently ignore errors during app shutdown (pool closed)
            NULL
        }
    )
}

save_bookmark_on_disconnect_impl <- function(session, input) {
    auth0_sub <- purrr::pluck(session$userData$auth0_info, "sub")
    if (purrr::is_empty(auth0_sub)) {
        log_debug("[BOOKMARKS] onSessionEnded: No auth0_sub, skipping")
        return(NULL)
    }

    # Generate unique state ID (alphanumeric only - Shiny rejects hyphens/special chars)
    state_id <- paste0(
        format(Sys.time(), "%Y%m%d%H%M%S"),
        substr(session$token, 1, 8)
    )

    # Create bookmark directory
    bookmark_dir <- getOption("bookmark_dir", "shiny_bookmarks")
    bookmark_path <- file.path(bookmark_dir, state_id)
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
            log_error("[BOOKMARKS] onSessionEnded: Failed to save input.rds: {e$message}")
            return(NULL)
        }
    )

    # Register in DB WITHOUT deleting old bookmarks.
    # Unlike explicit bookmark saves, disconnect saves should not delete previous bookmarks
    # because the user might be trying to restore that exact bookmark on reconnect.
    # Old bookmarks will be cleaned up by periodic cleanup (bookmark_cleanup in global.R).
    user <- db_get_or_create_user(auth0_sub)
    db_execute(
        "INSERT INTO bookmarks (user_id, state_id) VALUES ({user_id}, {state_id})",
        user_id = user$id,
        state_id = state_id
    )

    log_info("[BOOKMARKS] onSessionEnded: Saved bookmark {state_id} for user {user$id}")
    return(state_id)
}

# Register bookmark and cleanup previous ones for this user.
# Called from onBookmark callback.
register_user_bookmark <- function(user_id, state_id) {
    old_state_ids <- db_register_bookmark(user_id, state_id)
    delete_bookmark_folders(old_state_ids)

    if (length(old_state_ids) > 0) {
        log_info("[BOOKMARKS] User {user_id} - replaced {length(old_state_ids)} old bookmark(s) with {state_id}")
    } else {
        log_info("[BOOKMARKS] User {user_id} - created bookmark {state_id}")
    }
}
