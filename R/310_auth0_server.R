# Auth0 / Users admin sub-tab server
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

auth0_server <- function(id, is_active) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # ------ MODULE: Active Sessions ---------------------------------------
        active_sessions_server("active_sessions", is_active = is_active)

        # ------ REACTIVE: Recent Users ----------------------------------------
        # Poll every 60 seconds for recent users (only while tab is visible)
        recent_users <- reactivePoll(
            intervalMillis = 60 * 1000,
            session = session,
            checkFunc = function() {
                if (!isTRUE(is_active())) {
                    return(NULL)
                }
                purrr::possibly(\() nrow(db_get_recent_users(days = 7)), otherwise = 0)()
            },
            valueFunc = function() {
                req(is_active()) # Prevent execution when tab becomes inactive
                purrr::possibly(\() db_get_recent_users(days = 7), otherwise = data.frame())()
            }
        )

        # ------ OUTPUT: Recent Users Table ------------------------------------
        output$recent_users_table <- renderTable(
            {
                users <- recent_users()

                if (purrr::is_empty(users) || nrow(users) == 0) {
                    return(data.frame(Message = tr("No recent connections")))
                }

                # Fetch user details from Auth0 for display names (cached)
                users$name <- purrr::map_chr(users$auth0_sub, \(sub) {
                    user <- get_user_cached(sub)
                    purrr::pluck(user, "nickname") %||% purrr::pluck(user, "email") %||% sub
                })

                # Format for display
                data.frame(
                    Name = users$name,
                    `Last Connected` = format(
                        as.POSIXct(users$last_connected, tz = "UTC"),
                        "%Y-%m-%d %H:%M"
                    ),
                    Connections = users$connection_count,
                    check.names = FALSE
                )
            },
            striped = TRUE,
            hover = TRUE,
            width = "auto"
        )
    })
}
