# OTel Trace Viewer Server (app-specific)
# Uses reusable utilities from R/shiny-utils/otel.R
#
# NOTE: This module is disabled in production (ENV=prod). The UI shows
# a static message, and the server exits early to avoid unnecessary overhead.
#
# @param is_active Reactive boolean, TRUE when Traces tab is visible

otel_server <- function(id, is_active) {
    moduleServer(id, function(input, output, session) {
        # Exit early in production - UI shows disabled message
        if (isTRUE(is_prod)) {
            return()
        }

        ns <- session$ns

        # Span cache manager (handles accumulation and deduplication)
        span_cache <- otel_span_cache(OTEL_TRACER_PROVIDER)

        # Track known span IDs to detect new/expired spans for UI updates
        known_spans <- reactiveVal(character(0))

        # ----- REACTIVE: Fetch spans ------------------------------------------
        # Only fetches when tab becomes active or refresh is triggered
        spans_data <- reactive({
            # Re-run when refresh is triggered
            watch("refresh_otel")
            # Re-run when tab becomes active
            req(is_active(), otel_available())

            # Fetch new spans from provider into cache
            span_cache$fetch()

            # Get filtered spans from cache
            time_filter_mins <- as.integer(input$time_filter %||% "5")
            span_cache$get(time_filter_mins)
        })

        # ----- OUTPUT: Span count ---------------------------------------------
        output$span_count <- renderText({
            spans <- spans_data()
            if (is.null(spans) || nrow(spans) == 0) {
                tr("No spans")
            } else {
                sprintf("%d spans", nrow(spans))
            }
        })

        # ----- OUTPUT: Not configured state -----------------------------------
        output$not_configured <- renderUI({
            if (!otel_available()) {
                # Hide container, show message
                shinyjs::hide("rows_container")
                shinyjs::hide("empty_state")
                return(div(
                    class = "alert alert-info",
                    tags$h5(class = "alert-heading", tr("OTel not configured")),
                    p(tr("To enable OpenTelemetry tracing:")),
                    tags$ol(
                        tags$li("Install: ", tags$code("pak::pak(c('otel', 'otelsdk'))")),
                        tags$li("Restart the app")
                    )
                ))
            }
            NULL
        })

        # ----- OBSERVER: Row updates (insert/remove) --------------------------
        observe(label = "otel_row_updates", {
            spans <- spans_data()
            prev_ids <- isolate(known_spans())

            # Handle empty state
            if (is.null(spans) || nrow(spans) == 0) {
                known_spans(character(0))
                # Clear all rows and show empty state
                shinyjs::runjs(sprintf(
                    "document.getElementById('%s').innerHTML = '';",
                    ns("rows_container")
                ))
                shinyjs::show("empty_state")
                shinyjs::show(selector = sprintf("#%s", ns("rows_container")))
                return()
            }

            # Has data - hide empty state
            shinyjs::hide("empty_state")
            shinyjs::show(selector = sprintf("#%s", ns("rows_container")))

            current_ids <- spans$span_id

            # Find new and expired spans
            new_ids <- setdiff(current_ids, prev_ids)
            expired_ids <- setdiff(prev_ids, current_ids)

            # Update known spans
            known_spans(current_ids)

            # Skip if nothing changed
            if (length(new_ids) == 0 && length(expired_ids) == 0) {
                return()
            }

            js_commands <- character(0)

            # Insert new spans at the top
            if (length(new_ids) > 0) {
                new_spans <- spans[spans$span_id %in% new_ids, ]
                # Note: We do NOT re-sort by start_time here, as we want to preserve the
                # hierarchy/order from otel_prepare_hierarchy().
                # We insert in reverse order (bottom to top) so that the first element
                # ends up at the top via 'afterbegin'.

                for (i in rev(seq_len(nrow(new_spans)))) {
                    row_html <- as.character(otel_render_row(new_spans[i, ]))
                    js_commands <- c(
                        js_commands,
                        sprintf(
                            "var c = document.getElementById('%s'); if (c) c.insertAdjacentHTML('afterbegin', %s);",
                            ns("rows_container"),
                            jsonlite::toJSON(row_html, auto_unbox = TRUE)
                        )
                    )
                }
            }

            # Remove expired spans
            for (expired_id in expired_ids) {
                js_commands <- c(
                    js_commands,
                    sprintf(
                        "var el = document.getElementById('otel-row-%s'); if (el) el.remove();",
                        expired_id
                    )
                )
            }

            if (length(js_commands) > 0) {
                shinyjs::runjs(paste(js_commands, collapse = "\n"))
            }
        })

        # ----- OBSERVERS ------------------------------------------------------

        # Show busy state when tab opens (first active)
        observeEvent(is_active(), label = "otel_tab_open_busy", {
            req(is_active(), otel_available())
            bslib::update_task_button("refresh", state = "busy")
        })

        # Reset button after spans load
        observe(label = "otel_reset_busy", {
            spans_data() # Depend on spans loading
            bslib::update_task_button("refresh", state = "ready")
        })

        observeEvent(input$refresh, trigger("refresh_otel"), label = "otel_refresh")

        observeEvent(input$clear, label = "otel_clear", {
            # Clear the span cache
            span_cache$clear()
            known_spans(character(0))
            trigger("refresh_otel")
        })

        # Reset state when time filter changes
        observeEvent(input$time_filter, label = "otel_time_filter", {
            # Clear known spans to trigger full re-insert
            known_spans(character(0))
            # Clear existing rows
            shinyjs::runjs(sprintf(
                "document.getElementById('%s').innerHTML = '';",
                ns("rows_container")
            ))
            # Trigger refresh to reload with new filter
            trigger("refresh_otel")
        })
    })
}
