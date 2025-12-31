# Active Sessions server module
# Fetches and displays currently active sessions as cards
# Includes role management for active sessions
#
# @param is_active Reactive boolean, TRUE when the Users tab is visible.
#   Used to pause polling when user is on a different tab.
# @param r Shared reactiveValues - reads r$admin_show_only_recent

active_sessions_server <- function(id, is_active, r) {
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

        # ------ REACTIVE: Auth0 Roles -----------------------------------------
        all_roles <- reactive({
            req(is_active())
            get_roles_cached()
        })

        # ------ OUTPUT: Session Cards -----------------------------------------
        output$cards <- renderUI({
            sessions <- active_sessions()
            show_only_recent <- isTRUE(r$admin_show_only_recent)

            if (purrr::is_empty(sessions) || nrow(sessions) == 0) {
                return(div(
                    class = "text-muted",
                    tags$em(tr("No active sessions"))
                ))
            }

            # For each user_id, find the most recently active session (by updated_at)
            sessions_dt <- data.table::as.data.table(sessions)
            data.table::setorder(sessions_dt, user_id, -updated_at)
            most_recent_by_user <- sessions_dt[, .SD[1L], by = user_id]$id

            # Filter to only most recent if checkbox is checked
            if (show_only_recent) {
                sessions <- sessions[sessions$id %in% most_recent_by_user, ]
            }

            # Build cards for each session
            cards <- purrr::pmap(sessions, \(id, session_token, user_id, auth0_sub, started_at, updated_at, ...) {
                user_info <- get_user_cached(auth0_sub)
                user_roles_full <- get_user_roles_cached(auth0_sub)

                session_info <- list(
                    session_token = session_token,
                    auth0_sub = auth0_sub,
                    started_at = started_at,
                    updated_at = updated_at
                )
                # Grey out older sessions (only relevant when showing all)
                is_inactive <- !show_only_recent && !(id %in% most_recent_by_user)
                session_card_ui(
                    user_info,
                    session_info = session_info,
                    is_inactive = is_inactive,
                    user_roles_full = user_roles_full,
                    ns = ns
                )
            })

            div(
                class = "d-flex flex-wrap gap-3",
                cards
            )
        })

        # ------ OBSERVE: Edit Role Modal -----------------------------------------
        observeEvent(input$edit_role, label = "show_edit_role_modal", {
            req(input$edit_role)
            auth0_sub <- input$edit_role$auth0_sub
            current_role_id <- input$edit_role$current_role_id
            req(nzchar(auth0_sub))

            # Store for confirmation handler
            session$userData$pending_role_edit <- list(auth0_sub = auth0_sub)

            # Build role choices (empty string = "user" default)
            roles <- all_roles()
            choices <- stats::setNames(
                c("", purrr::map_chr(roles, "id")),
                c("user", purrr::map_chr(roles, "name"))
            )

            showModal(modalDialog(
                title = tr("Change Role"),
                selectInput(
                    ns("new_role_select"),
                    label = NULL,
                    choices = choices,
                    selected = current_role_id
                ),
                footer = tagList(
                    modalButton(tr("Cancel")),
                    actionButton(ns("confirm_role_change"), tr("Save"), class = "btn-primary")
                ),
                size = "s"
            ))
        })

        observeEvent(input$confirm_role_change, label = "confirm_role_change", {
            pending <- session$userData$pending_role_edit
            req(pending)
            auth0_sub <- pending$auth0_sub
            new_role_id <- input$new_role_select
            req(nzchar(auth0_sub))

            # Get current user roles (cached, will be invalidated after change)
            current_roles <- get_user_roles_cached(auth0_sub)
            current_role_ids <- purrr::map_chr(current_roles, "id")

            # Remove all current roles first (single role mode)
            if (length(current_role_ids) > 0) {
                tryCatch(
                    {
                        auth0_mgmt$remove_user_roles(auth0_sub, current_role_ids)
                    },
                    error = \(e) {
                        log_error("[ADMIN] Failed to remove roles from {auth0_sub}: {e$message}")
                        showNotification(tr("Failed to update role"), type = "error")
                        return()
                    }
                )
            }

            # Assign new role if one was selected
            if (nzchar(new_role_id)) {
                tryCatch(
                    {
                        auth0_mgmt$assign_user_roles(auth0_sub, new_role_id)
                        invalidate_user_roles_cache(auth0_sub)
                        removeModal()
                        showNotification(tr("Role updated"), type = "message")
                    },
                    error = \(e) {
                        log_error("[ADMIN] Failed to assign role to {auth0_sub}: {e$message}")
                        showNotification(tr("Failed to update role"), type = "error")
                    }
                )
            } else {
                invalidate_user_roles_cache(auth0_sub)
                removeModal()
                showNotification(tr("Role set to user"), type = "message")
            }

            session$userData$pending_role_edit <- NULL
        })
    })
}
