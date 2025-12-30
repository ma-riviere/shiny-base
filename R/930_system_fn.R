# System module helper functions

#' Get current log file
#'
#' Returns the most recently modified log file in the log directory.
#'
#' @return Character path to the log file, or NULL if none found.
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

#' Colorize a log line for HTML display
#'
#' Parses log line format: LEVEL [timestamp] [tags...] message
#' Returns HTML with colored level and timestamp spans.
#'
#' @param line Character. A single log line.
#' @return Character. HTML string with color spans.
colorize_log_line <- function(line) {
    pattern <- "^(FATAL|ERROR|WARN|INFO|DEBUG|TRACE)\\s+(\\[.+?\\])\\s+((?:\\[.+?\\]\\s*)+)(.*)$"
    match <- regmatches(line, regexec(pattern, line))[[1]]

    if (length(match) == 5) {
        level <- match[2]
        timestamp <- match[3]
        tags <- trimws(match[4])
        message <- htmltools::htmlEscape(match[5])
        level_class <- paste0("log-level-", tolower(level))

        sprintf(
            '<span class="%s">%s</span> <span class="log-timestamp">%s</span> %s %s',
            level_class,
            level,
            timestamp,
            tags,
            message
        )
    } else {
        htmltools::htmlEscape(line)
    }
}
