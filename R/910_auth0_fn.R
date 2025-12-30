# Shows recently connected users table. Active sessions are handled by the 311 sub-module.
#
# @param is_active Reactive boolean, TRUE when the Users tab is visible.
#   Used to pause polling when user is on a different tab.

# Memoised Auth0 user lookup (5 min cache, shared across sessions)
# Defined outside moduleServer so cache persists across admin sessions
get_user_cached <- memoise::memoise(
    function(auth0_sub) {
        if (is.null(auth0_mgmt) || purrr::is_empty(auth0_sub)) {
            return(list(email = auth0_sub, nickname = NULL, picture = NULL))
        }
        tryCatch(
            auth0_mgmt$get_user(auth0_sub),
            error = \(e) {
                log_debug("[ADMIN] Failed to fetch user {auth0_sub}: {e$message}")
                list(email = auth0_sub, nickname = NULL, picture = NULL)
            }
        )
    },
    cache = cachem::cache_mem(max_age = 5 * 60)
)
