# Active Sessions server module
# Fetches and displays currently active sessions as cards
#
# @param is_active Reactive boolean, TRUE when the Users tab is visible.
#   Used to pause polling when user is on a different tab.

active_sessions_server <- function(id, is_active) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # ------ REACTIVE: Active Sessions -------------------------------------
        # Poll every 30 seconds for active sessions (only while tab is visible)
        active_sessions <- reactivePoll(
            intervalMillis = 30 * 1000,
            session = session,
            checkFunc = function() {
                if (!isTRUE(is_active())) {
                    return(NULL)
                }
                purrr::possibly(\() nrow(db_get_active_sessions()), otherwise = 0)()
            },
            valueFunc = function() {
                req(is_active()) # Prevent execution when tab becomes inactive
                purrr::possibly(db_get_active_sessions, otherwise = data.frame())()
            }
        )

        # ------ OUTPUT: Session Cards -----------------------------------------
        output$cards <- renderUI({
            sessions <- active_sessions()

            if (purrr::is_empty(sessions) || nrow(sessions) == 0) {
                return(div(
                    class = "text-muted",
                    tags$em(tr("No active sessions"))
                ))
            }

            # For each user_id, find the most recently active session (by updated_at)
            # All other sessions for that user will be greyed out
            sessions_dt <- data.table::as.data.table(sessions)
            data.table::setorder(sessions_dt, user_id, -updated_at)
            most_recent_by_user <- sessions_dt[, .SD[1L], by = user_id]$id

            # Build cards for each session
            cards <- purrr::pmap(sessions, \(id, session_token, user_id, auth0_sub, started_at, updated_at, ...) {
                user_info <- get_user_cached(auth0_sub)
                session_info <- list(
                    session_token = session_token,
                    started_at = started_at,
                    updated_at = updated_at
                )
                is_inactive <- !(id %in% most_recent_by_user)
                session_card_ui(user_info, session_info = session_info, is_inactive = is_inactive)
            })

            div(
                class = "d-flex flex-wrap gap-3",
                cards
            )
        })
    })
}
