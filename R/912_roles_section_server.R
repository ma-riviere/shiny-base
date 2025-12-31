# Roles Section server module
# Manages Auth0 roles: list, create, delete
# Compares with app-defined roles from permissions.yaml

roles_section_server <- function(id, is_active) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Trigger for refreshing roles list
        refresh_trigger <- reactiveVal(0)

        # ------ REACTIVE: Auth0 Roles -----------------------------------------
        auth0_roles <- reactive({
            refresh_trigger() # Dependency for manual refresh
            req(is_active())

            get_roles_cached()
        })

        # ------ REACTIVE: App Roles -------------------------------------------
        # Roles defined in data/permissions.yaml
        app_roles <- reactive({
            if (is.null(.ROLE_PERMISSIONS)) {
                return(character(0))
            }
            names(.ROLE_PERMISSIONS)
        })

        # ------ OUTPUT: Auth0 Roles List --------------------------------------
        output$auth0_roles_list <- renderUI({
            roles <- auth0_roles()
            app_role_names <- app_roles()

            if (purrr::is_empty(roles)) {
                return(div(
                    class = "list-group-item text-muted",
                    tags$em(tr("No roles defined in Auth0"))
                ))
            }

            auth0_role_names <- purrr::map_chr(roles, "name")

            div(
                class = "list-group list-group-flush",
                lapply(roles, \(role) {
                    in_app <- role$name %in% app_role_names
                    role_item_ui(role, ns = ns, in_app = in_app)
                })
            )
        })

        # ------ OUTPUT: App Roles List ----------------------------------------
        output$app_roles_list <- renderUI({
            roles <- app_roles()
            auth0_role_names <- purrr::map_chr(auth0_roles(), "name")

            if (purrr::is_empty(roles)) {
                return(div(
                    class = "list-group-item text-muted",
                    tags$em(tr("No roles defined in permissions.yaml"))
                ))
            }

            div(
                class = "list-group list-group-flush",
                lapply(roles, \(role_name) {
                    in_auth0 <- role_name %in% auth0_role_names
                    app_role_item_ui(role_name, in_auth0 = in_auth0)
                })
            )
        })

        # ------ MODAL: Add Role -----------------------------------------------
        observeEvent(input$add_role, label = "show_add_role_modal", {
            showModal(modalDialog(
                title = tr("Create New Role"),
                textInput(ns("new_role_name"), tr("Role Name"), placeholder = "e.g., editor"),
                textInput(ns("new_role_description"), tr("Description (optional)"), placeholder = ""),
                footer = tagList(
                    modalButton(tr("Cancel")),
                    actionButton(ns("confirm_add_role"), tr("Create"), class = "btn-primary")
                )
            ))
        })

        observeEvent(input$confirm_add_role, label = "create_role", {
            role_name <- trimws(input$new_role_name)
            role_desc <- trimws(input$new_role_description)

            if (!nzchar(role_name)) {
                showNotification(tr("Role name is required"), type = "error")
                return()
            }

            tryCatch(
                {
                    auth0_mgmt$create_role(name = role_name, description = role_desc)
                    # Clear cache and refresh
                    memoise::forget(get_roles_cached)
                    refresh_trigger(refresh_trigger() + 1)
                    removeModal()
                    showNotification(tr("Role created"), type = "message")
                },
                error = \(e) {
                    log_error("[ADMIN] Failed to create role '{role_name}': {e$message}")
                    showNotification(paste(tr("Failed to create role:"), e$message), type = "error")
                }
            )
        })

        # ------ OBSERVE: Delete Role ------------------------------------------
        observeEvent(input$delete_role, label = "delete_role", {
            req(input$delete_role)
            role_id <- input$delete_role$id
            role_name <- input$delete_role$name
            req(nzchar(role_id))

            # Confirmation modal
            showModal(modalDialog(
                title = tr("Delete Role"),
                p(sprintf(tr("Are you sure you want to delete the role '%s'?"), role_name)),
                p(class = "text-warning", tr("This will remove the role from all users.")),
                footer = tagList(
                    modalButton(tr("Cancel")),
                    actionButton(ns("confirm_delete_role"), tr("Delete"), class = "btn-danger")
                )
            ))

            # Store role_id for confirmation handler
            session$userData$pending_delete_role_id <- role_id
        })

        observeEvent(input$confirm_delete_role, label = "confirm_delete_role", {
            role_id <- session$userData$pending_delete_role_id
            req(nzchar(role_id))

            tryCatch(
                {
                    auth0_mgmt$delete_role(role_id)
                    # Clear cache and refresh
                    memoise::forget(get_roles_cached)
                    refresh_trigger(refresh_trigger() + 1)
                    removeModal()
                    showNotification(tr("Role deleted"), type = "message")
                },
                error = \(e) {
                    log_error("[ADMIN] Failed to delete role: {e$message}")
                    showNotification(paste(tr("Failed to delete role:"), e$message), type = "error")
                }
            )

            session$userData$pending_delete_role_id <- NULL
        })
    })
}
