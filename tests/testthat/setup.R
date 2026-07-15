# Bypass Auth0 (env-only since auth0r 0.4.0; inherited by the AppDriver's R
# subprocess) and grant the admin dev role so permission-gated features stay
# testable (auth0r no longer implies admin in bypass mode). Must be set before
# load_app_env() runs global.R.
Sys.setenv(AUTH0_DISABLE = "true", DEV_ROLES = "admin")

# Load application support files into testing environment
shinytest2::load_app_env()

# if nzchar(Sys.getenv("GITHUB_ACTIONS") -> setup actions specific to GH actions pipeline (e.g. tests job)

app <- shinytest2::AppDriver$new(
    name = "ALL",
    height = 1080,
    width = 1920,
    load_timeout = 30000,
    timeout = 30000,
    options = list(warn = 2, shiny.testmode = TRUE)
)
