library(testthat)

test_that("App loads and works", {
    check_shiny_errors(app)
    check_shiny_crash(app)
})

test_that("the dataset assistant is absent when CHAT_ENABLED is off", {
    expect_false(app$get_js("document.querySelector('#explore-chat-launcher') !== null"))
})
