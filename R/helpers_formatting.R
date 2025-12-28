# Formatting helpers

# Format a timestamp as relative time (e.g., "5 min ago")
#
# @param timestamp POSIXct or character timestamp (assumed UTC)
# @return Translated relative time string
format_relative_time <- function(timestamp) {
    if (is.null(timestamp) || is.na(timestamp)) {
        return("")
    }
    time <- as.POSIXct(timestamp, tz = "UTC")
    diff_mins <- as.numeric(difftime(Sys.time(), time, units = "mins"))

    if (diff_mins < 1) {
        tr("just now")
    } else if (diff_mins < 60) {
        tr("%.0f min ago", diff_mins)
    } else if (diff_mins < 1440) {
        tr("%.1f hours ago", diff_mins / 60)
    } else {
        tr("%.0f days ago", diff_mins / 1440)
    }
}
