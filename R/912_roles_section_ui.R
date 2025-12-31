# Roles Section UI module
# Displays Auth0 roles vs app-defined roles, with ability to add/remove Auth0 roles

roles_section_ui <- function(id) {
    ns <- NS(id)
    div(
        class = "row g-4",
        # Left column: Auth0 roles
        div(
            class = "col-md-6",
            bslib::card(
                bslib::card_header(
                    class = "d-flex justify-content-between align-items-center card-header-accent",
                    tags$h5(class = "i18n mb-0", `data-key` = "Auth0 Roles", tr("Auth0 Roles")),
                    actionButton(
                        ns("add_role"),
                        label = NULL,
                        icon = bsicons::bs_icon("plus-lg"),
                        class = "btn-sm btn-outline-primary"
                    )
                ),
                bslib::card_body(
                    class = "p-0",
                    uiOutput(ns("auth0_roles_list"))
                )
            )
        ),
        # Right column: App-defined roles
        div(
            class = "col-md-6",
            bslib::card(
                bslib::card_header(
                    class = "d-flex align-items-center card-header-accent",
                    tags$h5(class = "i18n mb-0", `data-key` = "App Roles", tr("App Roles")),
                    span(
                        class = "text-muted small ms-2",
                        "(data/permissions.yaml)"
                    )
                ),
                bslib::card_body(
                    class = "p-0",
                    uiOutput(ns("app_roles_list"))
                )
            )
        )
    )
}

# Single role item for the Auth0 roles list
# @param role Role object with id, name, description
# @param ns Namespace function
# @param in_app Whether this role is also defined in the app's permissions.yaml
role_item_ui <- function(role, ns, in_app = FALSE) {
    div(
        class = "list-group-item d-flex justify-content-between align-items-center",
        div(
            div(
                class = "d-flex align-items-center mb-1",
                span(class = "fw-medium", role$name),
                if (in_app) {
                    tags$span(
                        class = "badge bg-success ms-2",
                        title = tr("Also defined in app"),
                        bsicons::bs_icon("check-circle")
                    )
                }
            ),
            if (nzchar(role$description %||% "")) {
                div(class = "text-muted small", role$description)
            }
        ),
        tags$button(
            type = "button",
            class = "btn btn-sm btn-outline-danger",
            onclick = sprintf(
                "Shiny.setInputValue('%s', {id: '%s', name: '%s', ts: Date.now()});",
                ns("delete_role"),
                role$id,
                role$name
            ),
            bsicons::bs_icon("trash")
        )
    )
}

# Single role item for the App roles list (read-only)
# @param role_name Role name
# @param in_auth0 Whether this role exists in Auth0
app_role_item_ui <- function(role_name, in_auth0 = FALSE) {
    div(
        class = "list-group-item d-flex justify-content-between align-items-center",
        span(role_name),
        if (in_auth0) {
            tags$span(
                class = "badge bg-success",
                title = tr("Exists in Auth0"),
                bsicons::bs_icon("check-circle")
            )
        } else {
            tags$span(
                class = "badge bg-warning text-dark",
                title = tr("Missing in Auth0"),
                bsicons::bs_icon("exclamation-triangle")
            )
        }
    )
}
