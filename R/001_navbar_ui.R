# Navbar UI elements
# Contains the right-side navbar items: language selector and user dropdown

navbar_ui <- function(id) {
    ns <- NS(id)

    tagList(
        # Navigation panels
        bslib::nav_panel(
            title = tags$span(class = "i18n", `data-key` = "Home", "Home"),
            value = "home",
            home_ui("home")
        ),
        bslib::nav_panel(
            title = tags$span(class = "i18n", `data-key` = "Explore", "Explore"),
            value = "explore",
            explore_ui("explore")
        ),
        bslib::nav_panel(
            title = tags$span(class = "i18n", `data-key` = "Model", "Model"),
            value = "model",
            model_ui("model")
        ),
        # Only shown for users with view:admin permission
        bslib::nav_panel(
            title = tags$span(class = "i18n", `data-key` = "Admin", tr("Admin")),
            value = "admin",
            admin_ui("admin")
        ),
        # Right side: language selector and user menu
        bslib::nav_spacer(),
        bslib::nav_item(navbar_language_selector(ns)),
        navbar_user_menu(ns)
    )
}

# ----- NAVBAR COMPONENTS ------------------------------------------------------

navbar_language_selector <- function(ns) {
    selectInput(
        ns("language"),
        label = NULL,
        choices = get_language_choices(),
        selected = i18n$get_key_translation(),
        width = "100px"
    )
}

navbar_user_menu <- function(ns) {
    bslib::nav_menu(
        title = tagList(
            tags$span(
                class = "user-nickname",
                textOutput(ns("user_nickname"), inline = TRUE)
            ),
            bsicons::bs_icon("list", class = "dropdown-hamburger ms-1")
        ),
        align = "right",
        bslib::nav_item(
            tags$a(
                id = ns("profile_link"),
                class = "dropdown-item",
                href = "#",
                onclick = sprintf(
                    "Shiny.setInputValue('%s', Date.now(), {priority: 'event'})",
                    ns("open_profile")
                ),
                bsicons::bs_icon("person"),
                tags$span(class = "i18n ms-2", `data-key` = "Profile", tr("Profile"))
            )
        ),
        "----",
        bslib::nav_item(
            tags$div(
                id = ns("logout_wrapper"),
                auth0r::logout_button(
                    label = tagList(
                        bsicons::bs_icon("box-arrow-right"),
                        tags$span(class = "i18n ms-2", `data-key` = "Logout", tr("Logout"))
                    ),
                    class = "dropdown-item logout-item"
                )
            )
        )
    )
}
