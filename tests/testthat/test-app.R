library(testthat)

test_that("App loads and works", {
    check_shiny_errors(app)
    check_shiny_crash(app)
})
