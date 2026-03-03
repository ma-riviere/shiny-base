# Model module helper functions

# Compute fit metrics from a model object
# Returns list with r_squared, rmse, aic, summary_text
model_compute_metrics <- function(model) {
    summ <- summary(model)
    list(
        r_squared = summ$r.squared,
        rmse = sqrt(mean(summ$residuals^2)),
        aic = purrr::possibly(AIC, otherwise = NA_real_)(model),
        summary_text = paste(capture.output(print(summ)), collapse = "\n")
    )
}

# Async model fitting task body (runs in mirai subprocess)
# Returns list with success/failure and model/metrics or error info
model_fit_task <- function(data, formula_str, log_fn, metrics_fn) {
    tryCatch(
        {
            log_fn("DEBUG", "Fitting model with formula: ", formula_str)

            # Validate and parse formula
            formula_obj <- as.formula(formula_str)

            # Get variables from formula
            vars <- all.vars(formula_obj)

            # Check if all variables exist
            missing_vars <- setdiff(vars, colnames(data))
            if (length(missing_vars) > 0) {
                log_fn("ERROR", "Variables not found: ", paste(missing_vars, collapse = ", "))
                stop(paste("Variables not found in data:", paste(missing_vars, collapse = ", ")))
            }

            # Fit model with na.action to handle missing values
            fit <- lm(formula_obj, data = data, na.action = na.exclude)

            # Replace formula_obj in call with actual formula for readable summary output
            fit$call$formula <- formula_obj

            # Extract metrics BEFORE butchering (butcher removes components summary() needs)
            metrics <- metrics_fn(fit)

            # Reduce model size for storage - apply only specific axe methods
            # Skip axe_call to preserve the formula in summary output
            fit <- fit |>
                butcher::axe_env() |>
                butcher::axe_fitted()
            fit$model <- NULL # No axe_data.lm, remove manually

            list(
                success = TRUE,
                model = fit,
                r_squared = metrics$r_squared,
                rmse = metrics$rmse,
                aic = metrics$aic,
                summary_text = metrics$summary_text
            )
        },
        error = function(e) {
            log_fn("ERROR", "Fit failed: ", e$message)
            log_fn("ERROR", "Call: ", deparse(e$call))
            tb <- paste(capture.output(traceback()), collapse = "\n")
            log_fn("ERROR", "Traceback: ", tb)

            list(
                success = FALSE,
                message = e$message,
                call = deparse(e$call),
                traceback = tb
            )
        }
    )
}

# Load a saved model from DB and update module state
#
# @param model_id Model ID to load
# @param session Shiny session (for updateTextInput)
# @param values Module reactiveValues (fitted_model, metrics, loaded_model_id will be updated)
# @param data Data frame to restore fitted values (butchered models lose this)
# @param silent_fail If TRUE, suppress error toasts (used for background loading)
# @return TRUE if successful, FALSE otherwise
model_load_saved <- function(model_id, session, values, data = NULL, silent_fail = FALSE) {
    model_row <- db_get_model(model_id)
    if (is.null(model_row) || nrow(model_row) == 0) {
        if (!silent_fail) {
            show_toast(
                title = tr("Model not found"),
                type = "error",
                timer = 3000,
                position = "bottom-end"
            )
        }
        return(FALSE)
    }

    blob_data <- model_row$model_blob
    if (is.null(blob_data) || length(blob_data) == 0 || is.null(blob_data[[1]])) {
        if (!silent_fail) {
            show_toast(
                title = tr("Model data corrupted"),
                type = "error",
                timer = 3000,
                position = "bottom-end"
            )
        }
        return(FALSE)
    }

    tryCatch(
        {
            loaded_model <- db_unserialize_model(blob_data[[1]])

            # Restore fitted.values for summary() - axe_fitted removes these
            if (!is.null(data)) {
                loaded_model$fitted.values <- predict(loaded_model, newdata = data)
            }

            values$fitted_model <- loaded_model
            values$metrics <- model_compute_metrics(loaded_model)
            values$loaded_model_id <- model_id

            updateTextInput(session, "equation", value = model_row$formula)
            shinyjs::show("results_section")
            shinyjs::enable("save_btn")
            shinyjs::enable("delete_btn")
            return(TRUE)
        },
        error = \(e) {
            if (!silent_fail) {
                show_toast(
                    title = tr("Error loading model"),
                    text = e$message,
                    type = "error",
                    timer = 5000,
                    position = "bottom-end"
                )
            }
            return(FALSE)
        }
    )
}
