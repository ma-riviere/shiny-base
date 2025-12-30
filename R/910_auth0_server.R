# Auth0 / Users admin sub-tab server

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
                    `Auth0 ID` = users$auth0_sub,
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
