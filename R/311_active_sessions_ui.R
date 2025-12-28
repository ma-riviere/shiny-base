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
#
# @param auth_info Auth0 user info object (or list with same structure)
# @param session_info Session info (session_token, started_at, updated_at)
# @param is_inactive Whether to grey out this card (not the most recent session for this user)
session_card_ui <- function(auth_info, session_info, is_inactive = FALSE) {
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
                div(class = "text-muted small", info$email),
                if (!purrr::is_empty(info$roles)) {
                    div(
                        class = "mt-1",
                        lapply(info$roles, \(role) {
                            tags$span(class = "badge bg-primary me-1", role)
                        })
                    )
                }
            ),
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
