ui <- function(request) {
    theme <- bslib::bs_theme(version = 5, bootswatch = "flatly")

    bslib::page_navbar(
        id = "nav",
        title = tags$span(
            class = "i18n",
            `data-key` = "Shiny Base",
            tr("Shiny Base")
        ),
        theme = theme,
        fillable = TRUE,
        navbar_options = bslib::navbar_options(
            position = "static-top",
            collapsible = TRUE,
            underline = FALSE
        ),
        header = tagList(
            # Serve js-cookie same-origin: cookies::cookie_dependency() declares it
            # with a CDN href that the CSP blocks (no Cookies global -> no cookie
            # input -> app init hangs). htmltools dedupes by name, highest version
            # wins, so this file-based copy (shipped in the cookies package)
            # replaces the CDN one.
            htmltools::htmlDependency(
                name = "js-cookie",
                version = "3.0.1.9000",
                src = "js",
                package = "cookies",
                script = "js.cookie.min.js"
            ),
            shinyutils::use_hex_loader(tr("Loading"), theme = theme),
            # Will be relocated/injected in <head> by Shiny
            tags$head(
                # Google Fonts with preconnect for better performance
                tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
                tags$link(
                    rel = "preconnect",
                    href = "https://fonts.gstatic.com",
                    crossorigin = NA
                ),
                tags$link(
                    rel = "stylesheet",
                    href = paste0(
                        "https://fonts.googleapis.com/css2?",
                        "family=Noto+Color+Emoji&",
                        "family=Open+Sans:wght@300..800&display=swap"
                    )
                ),
                tags$link(
                    rel = "stylesheet",
                    type = "text/css",
                    href = sprintf("css/main.min.css?v=%s", as.integer(Sys.time()))
                ),
                shinyutils::use_js_helpers(),
                tags$script(src = sprintf("js/app.js?v=%s", as.integer(Sys.time())))
            ),
            # auth0r >= 0.4.0 injects its client helpers (use_auth0) itself
            shinyjs::useShinyjs(),
            shiny.i18n::usei18n(i18n)
        ),
        sidebar = sidebar_ui("sidebar"),
        !!!navbar_ui("navbar")
    )
}

auth0r::auth0_ui_with_cookies(ui, info = auth0_config)
