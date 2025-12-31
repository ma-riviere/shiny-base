# Auth0 / Users admin sub-tab server
# @param r Shared reactiveValues - reads r$admin_users_view ("connected" or "all")

auth0_server <- function(id, is_active, r) {
    moduleServer(id, function(input, output, session) {
        # SECURITY GATE: prevent access without permission (UI is hidden, but server must also block)
        if (!can("view:admin:auth0")) {
            return()
        }

        ns <- session$ns

        # ------ VIEW SWITCHING ------------------------------------------------
        # Show correct section based on sidebar selection
        # Default to "connected" on first load
        observeEvent(
            r$admin_users_view,
            label = "auth0_view_switch",
            {
                view <- r$admin_users_view %||% "connected"
                if (view == "connected") {
                    shinyjs::show("section_connected")
                    shinyjs::hide("section_all")
                } else {
                    shinyjs::hide("section_connected")
                    shinyjs::show("section_all")
                }
            },
            ignoreNULL = FALSE
        )

        # ------ MODULE: Active Sessions ---------------------------------------
        active_sessions_server("active_sessions", is_active = is_active, r = r)

        # ------ MODULE: Roles Section -----------------------------------------
        roles_section_server("roles", is_active = is_active)

        # ------ REACTIVE: All Users -------------------------------------------
        # Poll every 60 seconds for all users (only while tab is visible and view is "all")
        all_users <- reactivePoll(
            intervalMillis = 60 * 1000,
            session = session,
            checkFunc = function() {
                if (!isTRUE(is_active()) || (r$admin_users_view %||% "connected") != "all") {
                    return(NULL)
                }
                purrr::possibly(\() nrow(db_get_all_users()), otherwise = 0)()
            },
            valueFunc = function() {
                req(is_active())
                req((r$admin_users_view %||% "connected") == "all")
                purrr::possibly(\() db_get_all_users(), otherwise = data.frame())()
            }
        )

        # ------ OUTPUT: All Users Cards ---------------------------------------
        output$all_users_cards <- renderUI({
            watch("refresh_user_cards")
            users <- all_users()

            if (purrr::is_empty(users) || nrow(users) == 0) {
                return(div(
                    class = "text-muted",
                    tags$em(tr("No users found"))
                ))
            }

            # Build cards for each user
            cards <- purrr::pmap(users, \(id, auth0_sub, created_at, connection_count, ...) {
                user_info <- get_user_cached(auth0_sub)
                user_roles_full <- get_user_roles_cached(auth0_sub)

                user_card_ui(
                    auth_info = user_info,
                    auth0_sub = auth0_sub,
                    user_roles_full = user_roles_full,
                    created_at = created_at,
                    connection_count = connection_count,
                    ns = ns
                )
            })

            div(
                class = "d-flex flex-wrap gap-3",
                cards
            )
        })

        # ------ REACTIVE: Auth0 Roles (for edit modal) --------------------------
        all_roles <- reactive({
            req(is_active())
            get_roles_cached()
        })

        # ------ OBSERVE: Edit Role Modal (for All Users view) -------------------
        observeEvent(input$edit_role, label = "auth0_show_edit_role_modal", {
            req(input$edit_role)
            auth0_sub <- input$edit_role$auth0_sub
            current_role_id <- input$edit_role$current_role_id
            req(nzchar(auth0_sub))

            # Store for confirmation handler
            session$userData$pending_role_edit <- list(auth0_sub = auth0_sub)

            # Build role choices
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

        observeEvent(input$confirm_role_change, label = "auth0_confirm_role_change", {
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
                        trigger("refresh_user_cards")
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
                trigger("refresh_user_cards")
                removeModal()
                showNotification(tr("Role set to user"), type = "message")
            }

            session$userData$pending_role_edit <- NULL
        })
    })
}
