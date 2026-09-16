# Check equation text before building a formula: model.frame() can execute formula code.
# E.g. y ~ x + system('...') would run a command during fitting.
# Parse the expression and check every part against allowed columns, numbers and functions.
# Only then build the formula, with an environment that supplies the approved functions.
# Ported from plumber-base (base-back/R/formula_safety.R).

FORMULA_ALLOWED_CALLS <- c("~", "+", "-", "*", ":", "^", "(", "I", "log", "sqrt", "poly")
FORMULA_MAX_CHARS <- 1000L

# Returns a formula object bound to the minimal environment, or stops with a
# client-safe reason.
validate_formula <- function(formula_str, column_names) {
    if (!is.character(formula_str) || length(formula_str) != 1 || !nzchar(trimws(formula_str))) {
        stop("formula must be a non-empty string", call. = FALSE)
    }
    if (nchar(formula_str) > FORMULA_MAX_CHARS) {
        stop("formula is too long", call. = FALSE)
    }
    node <- tryCatch(str2lang(formula_str), error = function(e) NULL)
    if (is.null(node)) {
        stop("formula cannot be parsed", call. = FALSE)
    }
    if (!is.call(node) || !identical(node[[1]], as.name("~")) || length(node) != 3) {
        stop("formula must be two-sided (response ~ terms)", call. = FALSE)
    }
    check_formula_node(node, column_names)
    return(eval(node, formula_environment()))
}

check_formula_node <- function(node, column_names) {
    if (is.name(node)) {
        name <- as.character(node)
        if (!name %in% column_names) {
            stop(sprintf("unknown variable '%s' (not a column of the dataset)", name), call. = FALSE)
        }
        return(invisible())
    }
    if (is.numeric(node) && length(node) == 1) {
        return(invisible())
    }
    if (is.call(node)) {
        head <- node[[1]]
        # Rejecting non-name heads blocks e.g. (function(x) ...)() and obj$fn().
        if (!is.name(head) || !as.character(head) %in% FORMULA_ALLOWED_CALLS) {
            stop(
                sprintf(
                    "disallowed function or operator '%s' in formula",
                    paste(deparse(head), collapse = "")
                ),
                call. = FALSE
            )
        }
        for (i in seq_along(node)[-1]) {
            # An empty arg (e.g. `poly(x,,2)`) is the empty symbol: it fails the
            # column-name check in the recursive call.
            check_formula_node(node[[i]], column_names)
        }
        return(invisible())
    }
    stop("disallowed element in formula", call. = FALSE)
}

# Give validated formulas access to their approved functions, including stats::poly().
# Use baseenv() as the parent: model.frame() also needs base functions such as list().
# With emptyenv(), every fit fails with "could not find function 'list'".
# The expression allowlist above is the security check. This environment keeps app globals
# and attached packages out of formula lookup, but still exposes base functions.
formula_environment <- function() {
    env <- new.env(parent = baseenv())
    for (fn in setdiff(FORMULA_ALLOWED_CALLS, "poly")) {
        env[[fn]] <- get(fn, envir = baseenv())
    }
    env$poly <- stats::poly
    return(env)
}
