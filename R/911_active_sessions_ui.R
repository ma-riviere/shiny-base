# Active Sessions UI module
# Displays mini profile cards for currently connected users
# Uses extract_profile_info() from shiny-utils/auth0.R
# Uses format_relative_time() from helpers_formatting.R

active_sessions_ui <- function(id) {
    ns <- NS(id)
    uiOutput(ns("cards"))
}

# User session card UI (display-only, for admin dashboard)
# Shows picture, email, roles, session info, and session ID.
# For active (non-greyed) cards, includes role display with edit button.
#
# @param auth_info Auth0 user info object (or list with same structure)
# @param session_info Session info (session_token, started_at, updated_at, auth0_sub)
# @param is_inactive Whether to grey out this card (not the most recent session for this user)
# @param user_roles_full List of user's current roles with full objects (id, name, description)
# @param ns Shiny namespace function (for input IDs)
session_card_ui <- function(auth_info, session_info, is_inactive = FALSE, user_roles_full = list(), ns = identity) {
    info <- extract_profile_info(auth_info)

    # Shorten session_token for display (first 8 chars)
    session_id_short <- if (!purrr::is_empty(session_info$session_token)) {
        substr(session_info$session_token, 1, 8)
    } else {
        ""
    }

    card_class <- paste(
        "user-profile-card",
        if (is_inactive) "inactive-session" else ""
    )

    bslib::card(
        class = card_class,
        style = paste0(
            "width: 220px; flex-shrink: 0;",
            if (is_inactive) " opacity: 0.5; filter: grayscale(50%);" else ""
        ),
        bslib::card_body(
            class = "d-flex flex-column align-items-center text-center gap-2 p-3",
            if (!purrr::is_empty(info$picture_url)) {
                tags$img(
                    src = info$picture_url,
                    class = "rounded-circle",
                    style = "width: 64px; height: 64px; object-fit: cover;",
                    alt = "Profile picture"
                )
            } else {
                div(
                    class = "rounded-circle bg-secondary d-flex align-items-center justify-content-center",
                    style = "width: 64px; height: 64px;",
                    tags$i(class = "bi bi-person-fill text-white fs-4")
                )
            },
            div(
                div(class = "fw-bold", info$nickname %||% info$email),
                div(class = "text-muted small", info$email)
            ),
            # Role display with edit button (only for active sessions)
            if (!is_inactive) {
                role_display_ui(
                    auth0_sub = session_info$auth0_sub,
                    user_roles_full = user_roles_full,
                    ns = ns
                )
            } else if (!purrr::is_empty(info$roles)) {
                # Static role badges for inactive sessions
                div(
                    class = "mt-1",
                    lapply(info$roles, \(role) {
                        tags$span(class = "badge bg-primary me-1", role)
                    })
                )
            },
            div(
                class = "text-muted small mt-1",
                span(tr("Connected:")),
                " ",
                span(format_relative_time(session_info$started_at))
            ),
            # Session ID
            div(
                class = "text-muted small font-monospace",
                style = "font-size: 0.75rem;",
                tags$code(session_id_short)
            )
        )
    )
}

# User card UI (for "All Users" view in admin dashboard)
# Shows picture, email, roles, creation date, and connection count.
# Includes role display with edit button.
#
# @param auth_info Auth0 user info object
# @param auth0_sub Auth0 user ID
# @param user_roles_full List of user's current roles with full objects
# @param created_at User creation timestamp
# @param connection_count Total number of sessions/connections for this user
# @param ns Shiny namespace function
user_card_ui <- function(
    auth_info,
    auth0_sub,
    user_roles_full = list(),
    created_at = NULL,
    connection_count = NULL,
    ns = identity
) {
    info <- extract_profile_info(auth_info)

    bslib::card(
        class = "user-profile-card",
        style = "width: 220px; flex-shrink: 0;",
        bslib::card_body(
            class = "d-flex flex-column align-items-center text-center gap-2 p-3",
            if (!purrr::is_empty(info$picture_url)) {
                tags$img(
                    src = info$picture_url,
                    class = "rounded-circle",
                    style = "width: 64px; height: 64px; object-fit: cover;",
                    alt = "Profile picture"
                )
            } else {
                div(
                    class = "rounded-circle bg-secondary d-flex align-items-center justify-content-center",
                    style = "width: 64px; height: 64px;",
                    tags$i(class = "bi bi-person-fill text-white fs-4")
                )
            },
            div(
                div(class = "fw-bold", info$nickname %||% info$email),
                div(class = "text-muted small", info$email)
            ),
            # Role display with edit button
            role_display_ui(
                auth0_sub = auth0_sub,
                user_roles_full = user_roles_full,
                ns = ns
            ),
            # Creation date and connection count
            div(
                class = "text-muted small mt-1",
                if (!is.null(created_at)) {
                    tagList(
                        span(tr("Created:")),
                        " ",
                        span(format(as.POSIXct(created_at, tz = "UTC"), "%Y-%m-%d"))
                    )
                },
                if (!is.null(connection_count)) {
                    div(
                        bsicons::bs_icon("box-arrow-in-right", class = "me-1"),
                        sprintf("%d %s", connection_count, tr("connections"))
                    )
                }
            )
        )
    )
}

# Role display with edit button for session cards
# Shows current role as badge + edit button that triggers modal
# Default role is "user" when no Auth0 roles are assigned
#
# @param auth0_sub Auth0 user ID
# @param user_roles_full List of user's current roles with full objects
# @param ns Shiny namespace function
role_display_ui <- function(auth0_sub, user_roles_full, ns) {
    # Get current role name (first one if multiple)
    # Default to "user" if no roles assigned
    current_role <- if (!purrr::is_empty(user_roles_full)) {
        purrr::pluck(user_roles_full, 1, .default = list(id = "", name = "user"))
    } else {
        list(id = "", name = "user")
    }

    # JavaScript to open edit modal
    onclick_js <- sprintf(
        "Shiny.setInputValue('%s', {auth0_sub: '%s', current_role_id: '%s', ts: Date.now()});",
        ns("edit_role"),
        auth0_sub,
        current_role$id %||% ""
    )

    div(
        class = "mt-1 d-flex align-items-center justify-content-center gap-1",
        tags$span(class = "badge bg-primary", current_role$name %||% "user"),
        tags$button(
            type = "button",
            class = "btn btn-sm btn-link p-0 ms-1",
            style = "font-size: 0.75rem;",
            onclick = onclick_js,
            title = tr("Edit role"),
            bsicons::bs_icon("pencil")
        )
    )
}
