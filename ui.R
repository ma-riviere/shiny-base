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
                tags$script(src = sprintf("js/helpers-modal.js?v=%s", as.integer(Sys.time())))
            ),
            auth0r::use_auth0(),
            shinyjs::useShinyjs(),
            shiny.i18n::usei18n(i18n),
            shinyWidgets::useSweetAlert()
        ),
        !!!navbar_ui("navbar")
    )
}

auth0r::auth0_ui_with_cookies(ui, info = auth0_info)
