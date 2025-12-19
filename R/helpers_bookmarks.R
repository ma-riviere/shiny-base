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
