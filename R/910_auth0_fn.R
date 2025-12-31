# Auth0 admin helpers
# Cached functions for Auth0 Management API calls

# Memoised Auth0 user lookup (5 min cache, shared across sessions)
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

# Memoised Auth0 roles list (5 min cache)
# Returns list of role objects with id, name, description
get_roles_cached <- memoise::memoise(
    function() {
        if (is.null(auth0_mgmt)) {
            return(list())
        }
        tryCatch(
            auth0_mgmt$list_roles(),
            error = \(e) {
                log_debug("[ADMIN] Failed to fetch roles: {e$message}")
                list()
            }
        )
    },
    cache = cachem::cache_mem(max_age = 5 * 60)
)

# Memoised user roles lookup (5 min cache)
# Returns list of role objects with id, name, description for a specific user
get_user_roles_cached <- memoise::memoise(
    function(auth0_sub) {
        if (is.null(auth0_mgmt) || purrr::is_empty(auth0_sub)) {
            return(list())
        }
        tryCatch(
            auth0_mgmt$get_user_roles(auth0_sub, full = TRUE),
            error = \(e) {
                log_debug("[ADMIN] Failed to fetch roles for {auth0_sub}: {e$message}")
                list()
            }
        )
    },
    cache = cachem::cache_mem(max_age = 5 * 60)
)

# Invalidate user roles cache for a specific user
# Call this after assigning/removing roles
invalidate_user_roles_cache <- function(auth0_sub) {
    memoise::drop_cache(get_user_roles_cached)(auth0_sub)
}
