server <- function(input, output, session) {
    session$allowReconnect(TRUE)

    # ------ ERROR HANDLING ----------------------------------------------------
    setup_error_handlers(session)

    # ------ USAGE TRACKING ----------------------------------------------------
    shinylogs::track_usage(
        storage_mode = shinylogs::store_json(
            path = getOption("shinylogs_dir", "data/shinylogs")
        )
    )

    # Exclude inputs that cause restoration issues:
    # - Auth0 params (code, state) to prevent token leakage (auth0r also excludes these but app's
    #   call overwrites auth0r's, so we must include them here)
    # - Action buttons with shinyActionButtonValue class
    # - Upload modal inputs (file, button, name) to prevent re-upload on bookmark restore
    # - Buttons that trigger modals (open_upload in home and dataset pages)
    shiny::setBookmarkExclude(c(
        "code",
        "state",
        "._auth0logout_",
        "sidebar-toggle",
        "upload-file",
        "upload-upload_btn",
        "upload-dataset_name",
        "home-open_upload",
        "dataset-open_upload"
    ))

    # ------ BOOKMARK ON DISCONNECT --------------------------------------------
    # Save bookmark state when user disconnects (closes tab, loses connection, etc.)
    # This runs after the WebSocket is closed, so we can't notify the user,
    # but the state is saved for restoration on their next session.
    if (!isTRUE(getOption("auth0_disable"))) {
        session$onSessionEnded(function() {
            save_bookmark_on_disconnect(pool, session, input)
        })
    }

    # ------ BOOKMARK TRACKING -------------------------------------------------
    # Register bookmarks in DB and clean up previous ones for this user.
    # Only runs when Auth0 is enabled (user identity required).
    onBookmark(function(state) {
        if (isTRUE(getOption("auth0_disable"))) {
            return()
        }

        auth0_sub <- purrr::pluck(session$userData$auth0_info, "sub")
        if (purrr::is_empty(auth0_sub)) {
            log_debug("[BOOKMARKS] No auth0_sub available, skipping tracking")
            return()
        }

        # Get or create user to get user_id
        user <- db_get_or_create_user(pool, auth0_sub)
        state_id <- basename(state$dir)

        register_user_bookmark(pool, user$id, state_id)
    })

    # ------ EMAIL VERIFICATION GATE -------------------------------------------
    # Modules are instantiated inside the gate to prevent unverified users from
    # accessing any app functionality. The gate uses observe() with bindEvent()
    # and once=TRUE to run exactly once when auth0_info becomes available.
    # When auth0_disable is TRUE, skip the gate entirely.

    init_modules <- function() {
        # Initialize event triggers for cross-module communication
        init("refresh_datasets", "show_upload_modal")

        # Store user in session$userData for cross-module access
        observe({
            auth_info <- session$userData$auth0_info
            if (purrr::is_empty(auth_info)) {
                return()
            }
            auth0_sub <- purrr::pluck(auth_info, "sub")
            if (purrr::is_empty(auth0_sub)) {
                return()
            }
            session$userData$user <- db_get_or_create_user(pool, auth0_sub)
        })

        navbar_server("navbar")
        sidebar_module <- sidebar_server("sidebar", active_page = reactive(input$nav))
        upload_dataset_server("upload")
        home_server(
            "home",
            row_count_filter = reactive(sidebar_module$row_count_filter),
            nav_select_callback = \(page) bslib::nav_select("nav", page, session = session)
        )
        dataset_server(
            "dataset",
            selected_dataset_id = reactive(sidebar_module$selected_dataset_id),
            nav_select_callback = \(page) bslib::nav_select("nav", page, session = session)
        )
    }

    if (isTRUE(getOption("auth0_disable"))) {
        init_modules()
        # Resolve language without Auth0 (cookie -> browser -> default)
        # Only apply if navbar language input doesn't already have a valid value
        # (e.g., from bookmark restoration)
        observe({
            current_lang <- input[["navbar-language"]]
            if (purrr::is_empty(current_lang) || current_lang == getOption("default_language", "en")) {
                resolved_lang <- resolve_language(NULL, session)
                apply_language(resolved_lang, session)
            }
        }) |>
            bindEvent(TRUE, once = TRUE)
    } else {
        observe({
            req(session$userData$auth0_info)

            if (!isTRUE(session$userData$auth0_info$email_verified)) {
                showModal(modalDialog(
                    title = "Email Verification Required",
                    p("Please verify your email address to access this application."),
                    actionButton("reload_page", "I've verified - Reload"),
                    footer = NULL,
                    easyClose = FALSE
                ))
                return()
            }

            init_modules()
        }) |>
            bindEvent(session$userData$auth0_info, once = TRUE)

        # ------ I18N ----------------------------------------------------------

        # Resolve and apply language preference using hierarchy:
        # 1. Auth0 user_metadata (source of truth)
        # 2. Cookie (remembers previous session choice)
        # 3. Browser language preference
        # 4. App default
        #
        # Only apply if navbar language doesn't already have a non-default value
        # (e.g., from bookmark restoration).
        observe({
            # Wait for auth0_info to be available
            req(session$userData$auth0_info)

            auth_info <- session$userData$auth0_info
            user_id <- purrr::pluck(auth_info, "sub")

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
            if (purrr::is_empty(current_lang) || current_lang == getOption("default_language", "en")) {
                resolved_lang <- resolve_language(session$userData$auth0_info, session)
                apply_language(resolved_lang, session)
            }
        }) |>
            bindEvent(session$userData$auth0_info, once = TRUE)
    }

    # Reload button (outside gate so it works for unverified users)
    observeEvent(input$reload_page, {
        session$reload()
    })

    # ------ BOOKMARK RESTORATION OFFER ----------------------------------------
    # On fresh login (not page refresh), check if user has a recent bookmark
    # and offer to restore it via a toast notification.
    observeEvent(
        input$session_status,
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
            if (isTRUE(getOption("auth0_disable"))) {
                return()
            }

            # Wait for auth0_info to be available
            auth0_sub <- purrr::pluck(session$userData, "auth0_info", "sub")
            if (purrr::is_empty(auth0_sub)) {
                return()
            }

            # Get user and check for recent bookmark
            user <- db_get_or_create_user(pool, auth0_sub)
            last_bookmark <- db_get_user_recent_bookmark(pool, user$id, max_age_minutes = 30)
            if (is.null(last_bookmark)) {
                return()
            }

            # Calculate age of bookmark in minutes
            created_time <- as.POSIXct(last_bookmark$created_at, tz = "UTC")
            current_time <- Sys.time()
            age_minutes <- as.numeric(difftime(current_time, created_time, units = "mins"))
            age_text <- if (age_minutes < 1) {
                "just now"
            } else if (age_minutes < 60) {
                sprintf("%.0f min ago", age_minutes)
            } else {
                sprintf("%.1f hours ago", age_minutes / 60)
            }

            restore_url <- paste0("/?_state_id_=", last_bookmark$state_id)

            shinyWidgets::show_toast(
                title = "Welcome Back",
                text = htmltools::HTML(paste0(
                    "You have a recent session (",
                    age_text,
                    "). ",
                    "<br><br>",
                    htmltools::tags$a(
                        href = restore_url,
                        class = "btn btn-primary btn-sm",
                        "Restore"
                    ),
                    " ",
                    htmltools::tags$button(
                        "Dismiss",
                        onclick = "Swal.close();",
                        class = "btn btn-default btn-sm"
                    )
                )),
                type = "info",
                timer = 30000,
                position = "top-end",
                timerProgressBar = TRUE
            )
        },
        ignoreInit = TRUE
    )
}

auth0r::auth0_server(server, info = auth0_info)
