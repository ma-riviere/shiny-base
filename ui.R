ui <- function(request) {
    bslib::page_navbar(
        id = "nav",
        title = tags$span(class = "i18n", `data-key` = "Shiny Base", tr("Shiny Base")),
        theme = bslib::bs_theme(
            version = 5,
            bootswatch = "flatly"
        ),
        fillable = TRUE,
        navbar_options = bslib::navbar_options(
            position = "static-top",
            collapsible = TRUE,
            underline = FALSE
        ),
        sidebar = sidebar_ui("sidebar"),
        header = tagList(
            tags$head(
                # Google Fonts with preconnect for better performance
                tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
                tags$link(rel = "preconnect", href = "https://fonts.gstatic.com", crossorigin = NA),
                tags$link(
                    rel = "stylesheet",
                    href = paste0(
                        "https://fonts.googleapis.com/css2?",
                        "family=Noto+Color+Emoji&",
                        "family=Open+Sans:wght@300..800&display=swap"
                    )
                ),
                tags$link(rel = "stylesheet", type = "text/css", href = "css/main.min.css"),
                tags$script(src = sprintf("js/helpers-auth0.js?v=%s", as.integer(Sys.time()))),
                tags$script(src = sprintf("js/helpers-modal.js?v=%s", as.integer(Sys.time())))
            ),
            shinyjs::useShinyjs(),
            shiny.i18n::usei18n(i18n)
        ),
        !!!navbar_ui("navbar")
    )
}

cookies::add_cookie_handlers(auth0_ui2(ui, info = auth0_info))
