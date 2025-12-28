# System admin sub-tab server
# Displays current log file content with auto-refresh
#
# @param is_active Reactive boolean, TRUE when the System tab is visible.
#   Used to pause polling when user is on a different tab.

system_server <- function(id, is_active) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # ------ HELPER: Get current log file ----------------------------------
        # Returns the most recently modified log file in the log directory
        get_current_log_file <- function() {
            log_dir <- getOption("log_dir", "logs")
            if (!dir.exists(log_dir)) {
                return(NULL)
            }

            log_files <- list.files(log_dir, pattern = "^app_.*\\.log$", full.names = TRUE)
            if (length(log_files) == 0) {
                return(NULL)
            }

            # Get the most recently modified file
            file_info <- file.info(log_files)
            log_files[which.max(file_info$mtime)]
        }

        # ------ REACTIVE: Log file content ------------------------------------
        # Poll every 10 seconds for log file changes (only while tab is visible)
        log_content <- reactivePoll(
            intervalMillis = 10 * 1000,
            session = session,
            checkFunc = function() {
                # Pause polling when tab is not visible
                if (!isTRUE(is_active())) {
                    return(NULL)
                }

                # Also react to manual refresh button
                watch("refresh_logs")

                log_file <- get_current_log_file()
                if (is.null(log_file) || !file.exists(log_file)) {
                    return(NULL)
                }
                # Use file modification time as check value
                file.info(log_file)$mtime
            },
            valueFunc = function() {
                req(is_active()) # Prevent execution when tab becomes inactive

                log_file <- get_current_log_file()
                if (is.null(log_file) || !file.exists(log_file)) {
                    return(list(name = NULL, content = tr("No log file found")))
                }

                # Read last 500 lines to avoid memory issues with large files
                lines <- purrr::possibly(readLines, otherwise = character(0))(log_file, warn = FALSE)

                if (length(lines) > 500) {
                    lines <- c(
                        paste0("... (", length(lines) - 500, " earlier lines omitted) ..."),
                        "",
                        tail(lines, 500)
                    )
                }

                list(
                    name = basename(log_file),
                    content = paste(lines, collapse = "\n")
                )
            }
        )

        # ------ OUTPUT: Log file name -----------------------------------------
        output$log_file_name <- renderText({
            log_data <- log_content()
            if (is.null(log_data$name)) {
                tr("No log file")
            } else {
                log_data$name
            }
        })

        # ------ OUTPUT: Log content -------------------------------------------
        output$log_content <- renderText(log_content()$content)

        # ------ OBSERVER: Manual refresh --------------------------------------
        observeEvent(input$refresh_logs, trigger("refresh_logs"))

        # ------ OBSERVER: Scroll to bottom ------------------------------------
        observeEvent(input$scroll_to_bottom, {
            shinyjs::runjs(sprintf(
                "document.getElementById('%s').scrollTop = document.getElementById('%s').scrollHeight;",
                ns("log_container"),
                ns("log_container")
            ))
        })
    })
}
