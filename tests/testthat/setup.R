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
