# Auth0 API Integration Class
#
# To use the Management API:
# 1. Applications > *your app* > APIs > Authorize the Management API
#    Then expand to add necessary permissions (read:users, update:users, etc.)
# 2. Applications > *your app* > Settings > Credentials
#    Set "Token Endpoint Authentication Method" to "Post" (not "None")
# 3. Applications > *your app* > Settings > Advanced Settings > Grant Types
#    Enable "Client Credentials" (required for Machine-to-Machine auth)

Auth0API <- R6::R6Class(
    classname = "Auth0API",
    public = list(
        domain = NULL,
        app_url = NULL,
        management_api_url = NULL,

        initialize = function(
            app_url = Sys.getenv("APP_URL"),
            port = Sys.getenv("APP_PORT")
        ) {
            self$app_url <- private$build_app_url(app_url, port)
            self$domain <- paste0("https://", Sys.getenv("AUTH0_DOMAIN"))
            self$management_api_url <- paste0(self$domain, "/api/v2/")
            private$management_token <- self$get_management_token()
        },

        get_jwks = function() {
            jwks_url <- paste0(self$domain, "/.well-known/jwks.json")
            httr2::request(jwks_url) |>
                httr2::req_perform() |>
                httr2::resp_body_json()
        },

        # ---- MANAGEMENT API --------------------------------------------------

        get_management_token = function() {
            httr2::request(paste0(self$domain, "/oauth/token")) |>
                httr2::req_body_json(list(
                    client_id = Sys.getenv("AUTH0_CLIENT_ID"),
                    client_secret = Sys.getenv("AUTH0_CLIENT_SECRET"),
                    audience = self$management_api_url,
                    grant_type = "client_credentials"
                )) |>
                httr2::req_error(is_error = \(resp) FALSE) |>
                httr2::req_perform() |>
                httr2::resp_body_json() |>
                purrr::pluck("access_token")
        },

        get_user_data = function(user_id) {
            httr2::request(paste0(self$management_api_url, "users/", user_id)) |>
                httr2::req_auth_bearer_token(private$management_token) |>
                httr2::req_error(is_error = \(resp) FALSE) |>
                httr2::req_perform() |>
                httr2::resp_body_json()
        },

        get_user_metadata = function(user_id) {
            self$get_user_data(user_id) |>
                purrr::pluck("user_metadata")
        },

        update_user_metadata = function(user_id, metadata) {
            httr2::request(paste0(self$management_api_url, "users/", user_id)) |>
                httr2::req_auth_bearer_token(private$management_token) |>
                httr2::req_method("PATCH") |>
                httr2::req_body_json(list(user_metadata = metadata)) |>
                httr2::req_error(is_error = \(resp) FALSE) |>
                httr2::req_perform() |>
                httr2::resp_body_json()
        },

        # Update user's nickname (stored in root user object, not user_metadata)
        update_user_nickname = function(user_id, nickname) {
            httr2::request(paste0(self$management_api_url, "users/", user_id)) |>
                httr2::req_auth_bearer_token(private$management_token) |>
                httr2::req_method("PATCH") |>
                httr2::req_body_json(list(nickname = nickname)) |>
                httr2::req_error(is_error = \(resp) FALSE) |>
                httr2::req_perform() |>
                httr2::resp_body_json()
        },

        get_user_app_metadata = function(user_id) {
            self$get_user_data(user_id) |>
                purrr::pluck("app_metadata")
        },

        get_user_roles = function(user_id) {
            roles <- httr2::request(paste0(self$management_api_url, "users/", user_id, "/roles")) |>
                httr2::req_auth_bearer_token(private$management_token) |>
                httr2::req_error(is_error = \(resp) FALSE) |>
                httr2::req_perform() |>
                httr2::resp_body_json()

            return(purrr::map_chr(roles, "name"))
        },

        # ---- UTILS -----------------------------------------------------------

        build_authorize_url = function(
            callback_path,
            scopes = c("openid", "profile", "email", "roles", "offline_access")
        ) {
            httr2::request(self$domain) |>
                httr2::req_url_path_append("authorize") |>
                httr2::req_url_query(
                    response_type = "code",
                    client_id = Sys.getenv("AUTH0_CLIENT_ID"),
                    redirect_uri = paste0(self$app_url, callback_path),
                    scope = paste(scopes, collapse = " ")
                ) |>
                purrr::pluck("url")
        },

        refresh_token = function(refresh_token) {
            httr2::request(paste0(self$domain, "/oauth/token")) |>
                httr2::req_body_json(list(
                    grant_type = "refresh_token",
                    client_id = Sys.getenv("AUTH0_CLIENT_ID"),
                    client_secret = Sys.getenv("AUTH0_CLIENT_SECRET"),
                    refresh_token = refresh_token
                )) |>
                httr2::req_error(is_error = \(resp) FALSE) |>
                httr2::req_perform() |>
                httr2::resp_body_json()
        },

        build_logout_url = function(id_token, return_url) {
            httr2::request(self$domain) |>
                httr2::req_url_path_append("v2", "logout") |>
                httr2::req_url_query(
                    id_token_hint = id_token,
                    client_id = Sys.getenv("AUTH0_CLIENT_ID"),
                    returnTo = return_url
                ) |>
                purrr::pluck("url")
        }
    ),

    private = list(
        management_token = NULL,

        build_app_url = function(app_url, port) {
            if (port != "") {
                app_url <- paste0(app_url, ":", port)
            }
            return(app_url)
        }
    )
)
