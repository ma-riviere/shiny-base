admin_ui <- function(id) {
    ns <- NS(id)
    div(
        id = ns("main"),
        class = "page page-admin",
        div(
            class = "page-header",
            h1(class = "i18n", `data-key` = "Admin Dashboard", tr("Admin Dashboard")),
            p(
                class = "lead i18n",
                `data-key` = "System administration and monitoring.",
                tr("System administration and monitoring.")
            )
        ),
        # ------ SUB-TABS ------------------------------------------------------
        bslib::navset_card_tab(
            id = ns("admin_tabs"),
            # ------ AUTH0 / USERS TAB -----------------------------------------
            bslib::nav_panel(
                title = tags$span(class = "i18n", `data-key` = "Users", tr("Users")),
                value = "users",
                auth0_ui(ns("auth0"))
            ),
            # ------ SYSTEM TAB ------------------------------------------------
            bslib::nav_panel(
                title = tags$span(class = "i18n", `data-key` = "System", tr("System")),
                value = "system",
                system_ui(ns("system"))
            )
        )
    )
}
