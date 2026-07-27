server <- function(input, output, session) {
    session$allowReconnect(TRUE)

    # ------ APP LOADER --------------------------------------------------------
    # Track initialization steps; hide loader when all complete
    init_state <- reactiveValues(
        auth = FALSE, # Auth0 check complete (or disabled)
        modules = FALSE # Modules initialized
    )
    restore_ready <- is_restore_ready(session)

    observe(label = "server_hide_loader", {
        req(init_state$auth, init_state$modules, restore_ready())
        waiter::waiter_hide()
    })

    # ------ ERROR HANDLING ----------------------------------------------------
    setup_session_error_emails(session)

    # ------ BOOKMARK EXCLUDES -------------------------------------------------
    # Inputs to exclude from bookmarks (used by both setBookmarkExclude and save_bookmark_on_disconnect):
    # - Auth0 params (code, state) to prevent token leakage
    # - Upload modal inputs (file, button) to prevent re-upload on restore
    # - Buttons that trigger modals
    # - Profile modal inputs (transient)
    bookmark_exclude <- c(
        "code",
        "state",
        "._auth0logout_",
        "sidebar-toggle",
        "upload-file",
        "upload-upload_btn",
        "upload-dataset_name",
        "home-open_upload",
        "dataset-open_upload",
        "navbar-open_profile",
        "profile-save_profile",
        "profile-profile_nickname",
        "profile-profile_language",
        "sidebar-admin_users_view",
        "sidebar-admin_show_only_recent",
        # Admin/role related inputs (modals, role management)
        "admin-auth0-ban_user",
        "admin-auth0-confirm_ban",
        "admin-auth0-edit_role",
        "admin-auth0-active_sessions-edit_role",
        "admin-auth0-roles-add_role",
        "admin-auth0-roles-new_role_name",
        "admin-auth0-roles-new_role_description",
        "admin-auth0-roles-confirm_add_role",
        "admin-auth0-roles-delete_role",
        "admin-auth0-roles-confirm_delete_role",
        # Model table delete button (side-effecting event-priority input).
        # Note: "model-selected_model" is intentionally NOT excluded - it carries
        # the model selection and must bookmark/restore like a normal input.
        "model-model_action_delete",
        # Dataset row inputs (side-effecting event-priority inputs; the selection
        # itself bookmarks via the sidebar's dataset select input)
        "home-dataset_click",
        "home-actions-edit",
        "home-actions-download",
        "home-actions-delete",
        "home-actions-confirm_delete",
        "explore-actions-edit",
        "explore-actions-download",
        "explore-actions-delete",
        "explore-actions-confirm_delete",
        # Rename modal inputs (transient, modal not open on restore)
        "edit_dataset-new_dataset_name",
        "edit_dataset-confirm_rename"
    )
    shiny::setBookmarkExclude(bookmark_exclude)

    # ------ SESSION TRACKING & BOOKMARK ON DISCONNECT --------------------------
    # Track session in DB and save bookmark when user disconnects.
    # onSessionEnded runs after WebSocket closes, so we can't notify the user.
    if (!auth0r::auth0_disabled()) {
        session$onSessionEnded(function() {
            # End session tracking (graceful disconnect)
            # Check pool validity first - onStop() may have closed it already
            if (!is.null(session$userData$session_db_id) && pool::dbIsValid(db_pool)) {
                tryCatch(
                    db_session_end(session$userData$session_db_id),
                    error = \(e) log_warn("[SESSION] Failed to end session: {e$message}")
                )
            }
            save_bookmark_on_disconnect(session, input, exclude = bookmark_exclude)
        })
    }

    # ------ BOOKMARK TRACKING -------------------------------------------------
    # Register bookmarks in DB and clean up previous ones for this user.
    # Only runs when Auth0 is enabled (user identity required).
    onBookmark(function(state) {
        if (auth0r::auth0_disabled()) {
            return()
        }

        auth0_sub <- purrr::pluck(session$userData$auth0_info, "sub")
        if (purrr::is_empty(auth0_sub)) {
            log_debug("[BOOKMARKS] No auth0_sub available, skipping tracking")
            return()
        }

        # Get or create user to get user_id
        user <- db_get_or_create_user(auth0_sub)
        state_id <- basename(state$dir)

        register_user_bookmark(user$id, state_id)
    })

    # ------ BOOKMARK RESTORATION CAPTURE --------------------------------------
    # Store entire state$input in session$userData during onRestore.
    # Modules created later can access via: session$userData$restored_state[["ns-inputId"]] %||% default
    # This is a general solution that works for any input without needing to enumerate them upfront.
    onRestore(function(state) {
        session$userData$restored_state <- state$input
        log_debug("[SERVER] onRestore: captured {length(state$input)} input values")
    })

    # ------ MODULE INITIALIZATION ---------------------------------------------
    # auth0_server() is default-deny (auth0r >= 0.4.0): this server function
    # only runs with validated claims, and the email-verified policy is
    # enforced by the authorize callback at the bottom of this file. When
    # AUTH0_DISABLE=true, the wrapper is bypassed entirely.

    init_modules <- function() {
        # Initialize event triggers for cross-module communication
        init(
            "refresh_datasets",
            "refresh_models",
            "refresh_user_cards",
            "show_upload_modal",
            "show_profile_modal",
            "profile_updated",
            "refresh_logs",
            "refresh_otel"
        )

        # Shared state for cross-module communication (explicit reactiveVals)
        # Each module receives only the reactiveVals it needs (read and/or write)
        selected_dataset_id <- reactiveVal(NULL)

        navbar_server("navbar")
        sidebar_module <- sidebar_server(
            "sidebar",
            selected_dataset_id = selected_dataset_id
        )

        # Auto-close sidebar on pages without sidebar content, pulse toggle when content available
        # CSS handles showing animation only when sidebar is closed (via :has(#sidebar-sidebar[hidden]))
        pages_with_sidebar <- c("home", "explore", "model")
        sidebar_toggle_selector <- "button[aria-controls='sidebar-sidebar']"
        observeEvent(input$nav, label = "server_sidebar_auto_close", {
            if (input$nav %in% pages_with_sidebar) {
                # Remove then re-add class to restart animation
                shinyjs::removeClass(
                    selector = sidebar_toggle_selector,
                    class = "sidebar-has-content"
                )
                shinyjs::delay(
                    10,
                    shinyjs::addClass(
                        selector = sidebar_toggle_selector,
                        class = "sidebar-has-content"
                    )
                )
            } else {
                bslib::toggle_sidebar("sidebar-sidebar", open = FALSE)
                shinyjs::removeClass(
                    selector = sidebar_toggle_selector,
                    class = "sidebar-has-content"
                )
            }
        })

        profile_modal_server("profile")
        upload_dataset_server("upload")
        edit_dataset_module <- edit_dataset_server("edit_dataset")
        home_server(
            "home",
            row_count_filter = reactive(sidebar_module$row_count_filter),
            age_filter = reactive(sidebar_module$age_filter),
            nav_select_callback = \(page) {
                bslib::nav_select("nav", page, session = session)
            },
            selected_dataset_id = selected_dataset_id,
            on_edit = edit_dataset_module$open
        )
        explore_server(
            "explore",
            selected_dataset_id = selected_dataset_id,
            nav_select_callback = \(page) {
                bslib::nav_select("nav", page, session = session)
            },
            on_edit = edit_dataset_module$open
        )
        model_server(
            "model",
            selected_dataset_id = selected_dataset_id,
            active_page = reactive(input$nav)
        )

        # Admin module - always instantiate but gated by req(can("view:admin")) inside
        admin_server("admin", active_page = reactive(input$nav))

        # Admin nav panel visibility:
        # - Hidden by default via nav_hide() (runs for all users)
        # - Shown via nav_show() only for users with view:admin permission
        # Panel exists at page load (required for bookmark restoration).
        bslib::nav_hide("nav", target = "admin")
        if (can("view:admin")) {
            bslib::nav_show("nav", target = "admin")
        }
    }

    if (auth0r::auth0_disabled()) {
        init_state$auth <- TRUE
        session$userData$user <- db_get_or_create_guest_user(session$token)
        init_modules()
        init_state$modules <- TRUE
        # Resolve language without Auth0 (cookie -> browser -> default)
        # Only apply if navbar language input doesn't already have a valid value
        # (e.g., from bookmark restoration)
        observe(label = "server_resolve_lang_no_auth", {
            current_lang <- input[["navbar-language"]]
            if (
                purrr::is_empty(current_lang) ||
                    current_lang == getOption("default_language", "en")
            ) {
                resolved_lang <- resolve_language(NULL, session)
                apply_language(resolved_lang, session)
            }
        }) |>
            bindEvent(TRUE, once = TRUE)
    } else {
        # Default-deny wrapper guarantees validated, authorized claims here:
        # session$userData is populated before this server function runs, so
        # the authenticated-user setup is ordinary synchronous initialization.
        auth0_sub <- purrr::pluck(session$userData$auth0_info, "sub")
        if (!purrr::is_empty(auth0_sub)) {
            # This app renders profile fields from Auth0, but the shared users
            # table is also read directly by plumber2-base (its admin panel has
            # no Management API lookup), so the claims are mirrored on login.
            session$userData$user <- db_get_or_create_user(
                auth0_sub,
                email = purrr::pluck(session$userData$auth0_info, "email"),
                nickname = purrr::pluck(session$userData$auth0_info, "nickname")
            )

            # Cross-app ban enforcement: users.status lives in the shared schema,
            # so a ban is instantly authoritative for the plumber2 API (checked on
            # every request). This login check and the heartbeat check below are
            # the Shiny-side equivalents, since a Shiny session is long-lived.
            if (!identical(session$userData$user$status, "active")) {
                log_warn("[AUTH] Rejecting {auth0_sub}: account status is {session$userData$user$status}")
                showNotification(tr("Your account has been suspended"), type = "error", duration = NULL)
                shinyjs::delay(3000, session$close())
                return()
            }

            # Start session tracking
            tryCatch(
                {
                    session$userData$session_db_id <- db_session_start(
                        session$token,
                        session$userData$user$id,
                        auth0_sub
                    )
                },
                error = \(e) {
                    log_warn("[SESSION] Failed to start session: {e$message}")
                }
            )
        }

        init_modules()
        init_state$auth <- TRUE
        init_state$modules <- TRUE

        # Session heartbeat: update updated_at every 5 minutes
        observe(label = "server_session_heartbeat", {
            invalidateLater(5 * 60 * 1000)
            # Only the heartbeat write depends on session tracking having started:
            # the ban check below must run even if db_session_start failed.
            if (!is.null(session$userData$session_db_id)) {
                tryCatch(
                    db_session_heartbeat(session$userData$session_db_id),
                    error = \(e) log_debug("[SESSION] Heartbeat failed: {e$message}")
                )
            }

            # Ban applied mid-session (from this app or the Auth0 dashboard poller):
            # only ever closes THIS session, never anyone else's.
            status <- tryCatch(db_get_user_status(session$userData$user$id), error = \(e) NULL)
            if (!is.null(status) && !identical(status, "active")) {
                log_warn("[AUTH] Closing session: account status is {status}")
                showNotification(tr("Your account has been suspended"), type = "error", duration = NULL)
                shinyjs::delay(3000, session$close())
            }
        })

        # ------ I18N ----------------------------------------------------------

        # Resolve and apply language preference using hierarchy:
        # 1. Auth0 user_metadata (source of truth)
        # 2. Cookie (remembers previous session choice)
        # 3. Browser language preference
        # 4. App default
        #
        # Only apply if navbar language doesn't already have a non-default value
        # (e.g., from bookmark restoration).
        observe(label = "server_resolve_lang_with_auth", {
            user_id <- purrr::pluck(session$userData$auth0_info, "sub")

            # Fetch user_metadata from Auth0 if we have a user_id
            if (!purrr::is_empty(user_id)) {
                tryCatch(
                    {
                        user_metadata <- auth0_mgmt$get_user_metadata(user_id)
                        # Store in session for profile modal
                        session$userData$auth0_info$user_metadata <- user_metadata
                    },
                    error = \(e) {
                        log_warn("[SERVER] Error fetching user_metadata: {e$message}")
                    }
                )
            }

            # Only apply if input doesn't already have a non-default value
            current_lang <- input[["navbar-language"]]
            if (
                purrr::is_empty(current_lang) ||
                    current_lang == getOption("default_language", "en")
            ) {
                resolved_lang <- resolve_language(session$userData$auth0_info, session)
                apply_language(resolved_lang, session)
            }
        }) |>
            bindEvent(TRUE, once = TRUE)
    }

    # ------ BOOKMARK RESTORATION OFFER ----------------------------------------
    # On fresh login (not page refresh), check if user has a recent bookmark
    # and offer to restore it via a toast notification.
    observeEvent(
        input$session_status,
        label = "server_bookmark_restore_offer",
        {
            if (input$session_status != "fresh_login") {
                return()
            }

            # Don't offer if URL already has a bookmark state (deep link takes priority)
            query <- shiny::parseQueryString(session$clientData$url_search)
            if (!is.null(query[["_state_id_"]])) {
                return()
            }

            # Skip if Auth0 is disabled (no user identity)
            if (auth0r::auth0_disabled()) {
                return()
            }

            # Wait for auth0_info to be available
            auth0_sub <- purrr::pluck(session$userData, "auth0_info", "sub")
            if (purrr::is_empty(auth0_sub)) {
                return()
            }

            # Get user and check for recent bookmark
            user <- db_get_or_create_user(auth0_sub)
            last_bookmark <- db_get_user_recent_bookmark(
                user$id,
                max_age_minutes = 30
            )
            if (is.null(last_bookmark)) {
                return()
            }

            # Calculate age of bookmark in minutes
            created_time <- as.POSIXct(last_bookmark$created_at, tz = "UTC")
            current_time <- Sys.time()
            age_minutes <- as.numeric(difftime(
                current_time,
                created_time,
                units = "mins"
            ))
            age_text <- if (age_minutes < 1) {
                tr("just now")
            } else if (age_minutes < 60) {
                tr("%.0f min ago", age_minutes)
            } else {
                tr("%.1f hours ago", age_minutes / 60)
            }

            restore_url <- paste0("/?_state_id_=", last_bookmark$state_id)

            bslib::show_toast(bslib::toast(
                htmltools::tags$div(
                    class = "d-flex align-items-center gap-3",
                    bsicons::bs_icon("clock-history", size = "1.5rem"),
                    htmltools::tags$div(
                        htmltools::tags$strong(tr("Welcome Back")),
                        htmltools::tags$div(
                            class = "small opacity-75 mb-2",
                            tr("You have a recent session (%s).", age_text)
                        ),
                        htmltools::tags$a(
                            href = restore_url,
                            class = "btn btn-primary btn-sm",
                            tr("Restore")
                        )
                    )
                ),
                htmltools::tags$div(
                    class = "toast-timer-bar",
                    style = "animation-duration: 30s;"
                ),
                id = "bookmark-restore",
                type = "info",
                duration_s = 30,
                position = "top-right",
                closable = TRUE
            ))
        },
        ignoreInit = TRUE
    )
}

# Default-deny: application server logic never runs without validated claims.
# The email-verified policy lives here (app policy, not package policy); denied
# sessions get an inert page with the display-safe reason below.
auth0r::auth0_server(
    server,
    info = auth0_config,
    authorize = function(claims, userinfo) {
        if (isTRUE(claims$email_verified %||% userinfo$email_verified)) {
            return(TRUE)
        }
        auth0r::auth0_authorization_result(
            FALSE,
            "Please verify your email address, then reload this page."
        )
    }
)
