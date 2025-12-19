# Helpers

wait <- function(app, t = 1) {
    app$wait_for_idle()
    Sys.sleep(t)
}

check_shiny_errors <- function(app) {
    error <- app$get_text(selector = ".shiny-output-error")
    testthat::expect_null(error)
}

check_shiny_crash <- function(app) {
    crash <- app$get_text(selector = "#shiny-disconnected-overlay")
    testthat::expect_null(crash)
}
