# Auth0 helper functions
#
# Custom wrappers around the auth0 package to handle bookmark preservation through Auth0 redirects.
#
# Why these customizations exist:
# - Standard auth0_ui includes query params in redirect_uri, which Auth0 rejects
# - We encode _state_id_ in Auth0's state parameter, keeping redirect_uri clean
# - After Auth0 callback, we redirect with _state_id_ to trigger Shiny's native restoration
# - bslib::page_navbar with id="nav" creates input$nav which is automatically bookmarked

# Build Auth0 logout URL from config
build_logout_url <- function(base_url) {
    config <- auth0::auth0_config()
    app_url_enc <- utils::URLencode(base_url, reserved = TRUE)
    sprintf(
        "%s/v2/logout?client_id=%s&returnTo=%s",
        purrr::pluck(config, "auth0_config", "api_url"),
        purrr::pluck(config, "auth0_config", "credentials", "key"),
        app_url_enc
    )
}

# Check for valid Auth0 code and state in request params
# State format: "originalState" or "originalState|bookmark_id"
has_valid_auth <- function(params, expected_state) {
    if (!purrr::is_empty(params$error) || purrr::is_empty(params$code) || purrr::is_empty(params$state)) {
        return(FALSE)
    }
    state_parts <- strsplit(params$state, "|", fixed = TRUE)[[1]]
    return(state_parts[1] == expected_state)
}

# Extract bookmark ID from Auth0 state param
# Returns NULL if no bookmark ID encoded
extract_bookmark_id <- function(state_param) {
    if (purrr::is_empty(state_param)) {
        return(NULL)
    }
    state_parts <- strsplit(state_param, "|", fixed = TRUE)[[1]]
    if (length(state_parts) == 2 && nzchar(state_parts[2])) {
        return(state_parts[2])
    }
    return(NULL)
}

# Custom auth0_ui that preserves bookmark state through Auth0 redirect.
#
# Flow:
# 1. User visits /?_state_id_=xxx -> encodes bookmark ID in Auth0 state, redirects to Auth0
# 2. Auth0 redirects back with ?code=...&state=originalState|xxx (no _state_id_)
# 3. If bookmark ID in state but no _state_id_ in URL -> redirect to add _state_id_
# 4. Now URL has both auth params AND _state_id_ -> Shiny's native restoration works
auth0_ui2 <- function(ui, info) {
    disable <- getOption("auth0_disable")
    if (!purrr::is_empty(disable) && disable) {
        return(ui)
    }

    if (missing(info)) {
        info <- auth0::auth0_info()
    }

    function(req) {
        params <- shiny::parseQueryString(req$QUERY_STRING)

        # Helper to detect protocol from request headers
        get_protocol <- function() {
            # Check X-Forwarded-Proto header (set by reverse proxies)
            forwarded_proto <- req$HTTP_X_FORWARDED_PROTO
            if (!is.null(forwarded_proto) && nzchar(forwarded_proto)) {
                return(paste0(forwarded_proto, "://"))
            }
            # Default to https in production, http for localhost
            if (grepl("localhost|127.0.0.1", req$HTTP_HOST)) {
                return("http://")
            }
            return("https://")
        }

        # Helper to build base URL from request
        build_redirect_uri <- function() {
            protocol <- get_protocol()
            host <- gsub("127.0.0.1", "localhost", req$HTTP_HOST)
            paste0(protocol, host, req$PATH_INFO)
        }

        if (!has_valid_auth(params, info$state)) {
            if (grepl("error=unauthorized", req$QUERY_STRING)) {
                protocol <- get_protocol()
                host <- gsub("127.0.0.1", "localhost", req$HTTP_HOST)
                base_url <- paste0(protocol, host)
                redirect <- sprintf("location.replace(\"%s\");", build_logout_url(base_url))
                return(shiny::tags$script(shiny::HTML(redirect)))
            }

            # Extract _state_id_ if present (server-side bookmark)
            state_id <- purrr::pluck(params, "_state_id_")

            # Build clean redirect_uri (without any query params)
            redirect_uri <- build_redirect_uri()
            redirect_uri <<- redirect_uri

            # Encode _state_id_ in Auth0's state parameter if present
            combined_state <- if (!purrr::is_empty(state_id) && nzchar(state_id)) {
                paste0(info$state, "|", state_id)
            } else {
                info$state
            }

            # Generate Auth0 authorization URL
            query_extra <- if (purrr::is_empty(info$audience)) list() else list(audience = info$audience)
            auth_url <- httr::oauth2.0_authorize_url(
                info$api,
                info$app(redirect_uri),
                scope = info$scope,
                state = combined_state,
                query_extra = query_extra
            )

            js_code <- sprintf("location.replace('%s');", auth_url)
            return(shiny::tags$script(shiny::HTML(js_code)))
        }

        # Authenticated via code - set redirect_uri for logout
        redirect_uri <<- build_redirect_uri()

        # Extract bookmark_id from Auth0 state param
        bookmark_id <- extract_bookmark_id(params$state)

        # If we have a bookmark ID but _state_id_ is not in URL, redirect to add it.
        # This triggers Shiny's native bookmark restoration.
        current_state_id <- params[["_state_id_"]]
        needs_state_redirect <- !purrr::is_empty(bookmark_id) &&
            (is.null(current_state_id) || !nzchar(current_state_id))

        if (needs_state_redirect) {
            # Build URL with all current params + _state_id_
            # Remove leading ? from QUERY_STRING if present
            query_string <- sub("^\\?", "", req$QUERY_STRING)
            redirect_url <- sprintf(
                "%s?%s&_state_id_=%s",
                build_redirect_uri(),
                query_string,
                bookmark_id
            )
            js_code <- sprintf("location.replace('%s');", redirect_url)
            return(shiny::tags$script(shiny::HTML(js_code)))
        }

        # Return the UI (bslib::page_navbar handles tab restoration via input$nav)
        if (is.function(ui)) ui(req) else ui
    }
}

# Custom auth0_server that handles token verification.
#
# Bookmark restoration is now handled by Shiny's native mechanism (triggered by _state_id_ in URL).
# The auth0_ui2 function redirects to include _state_id_ after Auth0 callback.
auth0_server2 <- function(server, info) {
    if (isTRUE(getOption("auth0_disable"))) {
        return(server)
    }

    if (missing(info)) {
        info <- auth0::auth0_info()
    }

    function(input, output, session) {
        # Token verification
        shiny::isolate({
            u_search <- session$clientData$url_search
            params <- shiny::parseQueryString(u_search)

            # Check for valid auth code - state may have "|bookmark_id" appended
            state_parts <- strsplit(params$state %||% "", "|", fixed = TRUE)[[1]]
            state_base <- state_parts[1]
            has_code <- is.null(params$error) && !is.null(params$code) && state_base == info$state

            if (has_code) {
                # Exchange code for token
                cred <- httr::oauth2.0_access_token(info$api, info$app(redirect_uri), params$code)
                token <- httr::oauth2.0_token(
                    app = info$app(redirect_uri),
                    endpoint = info$api,
                    cache = FALSE,
                    credentials = cred,
                    user_params = list(grant_type = "authorization_code")
                )

                # Fetch user info
                userinfo_url <- sub("authorize", "userinfo", info$api$authorize)
                resp <- httr::RETRY(
                    verb = "GET",
                    url = userinfo_url,
                    httr::config(token = token),
                    times = 5
                )

                assign("auth0_credentials", token$credentials, envir = session$userData)
                assign("auth0_info", httr::content(resp, "parsed"), envir = session$userData)
            }
        })

        # Logout handler
        shiny::observeEvent(input[["._auth0logout_"]], {
            base_url <- paste0(
                session$clientData$url_protocol,
                "//",
                session$clientData$url_hostname,
                if (nzchar(session$clientData$url_port)) paste0(":", session$clientData$url_port) else ""
            )
            shinyjs::runjs(sprintf("location.replace('%s');", build_logout_url(base_url)))
        })

        server(input, output, session)
    }
}
