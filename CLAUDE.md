# Shiny Base

Base template for Shiny apps with Auth0 authentication and server-side bookmarking.

**Auth0 credentials:** `ma.riviere987@gmail.com` / `auth0test&15`

**LLM Resource:** When unsure about Shiny-related issues, consult/brainstorm with the Shiny NotebookLM (skill).

---

# Project Map

## Tech Stack

- **Framework**: Shiny + bslib (Bootstrap 5)
- **Database**: PostgreSQL (prod) / SQLite (dev/test) via `pool`
- **Auth**: Auth0 via `ma-riviere/auth0r`
- **Email**: `blastula` via Brevo SMTP
- **Observability**: OpenTelemetry (Shiny 1.12+)

## Directory Structure

```
shiny-base/
├── global.R              # App-wide init, options, database pool
├── ui.R                  # Main UI, wraps Auth0, base-level modules
├── server.R              # Main server, module instantiation, bookmarking
├── R/                    # Modules and helpers
│   ├── 00x_*             # Shared sub-modules (navbar, sidebar, dataset_row)
│   ├── 1xx_*             # Home module
│   ├── 2xx_*             # Dataset (Explore) module
│   ├── 3xx_*             # Model module (async fitting via ExtendedTask)
│   ├── 9xx_*             # Admin module (always last)
│   ├── helpers_*.R       # Non-module functions (includes model DB ops)
│   └── shiny-utils/      # Reusable utilities (git submodule)
│       ├── logging.R, auth0.R, bookmarks.R, caching.R
│       ├── database.R, error_handling.R, i18n.R, loading.R
│       ├── otel.R, sass.R, scheduler.R, sessions.R
│       ├── triggers.R, users.R, validation.R
│       └── shinylogs.R   # (Unused) Session replay - see file for schema
├── www/                  # Static assets (css/, sass/, js/, html/, img/)
├── data/                 # translations.json
├── database/             # schema-base.sql (users, sessions, bookmarks), schema.sql (app-specific)
├── tests/                # shinytest2, testthat
├── _auth0.yml            # Auth0 configuration
├── .Renviron             # Environment variables
└── shiny_bookmarks/      # Server-side bookmark storage
```

---

# Architecture Decisions

## Auth0 Integration

**Choice:** Custom (private) `ma-riviere/auth0r` instead of `curso-r/auth0`.

**Why:** Native bookmarking support. Encodes `_state_id_` in Auth0's state parameter, keeping redirect URIs clean.

## Bookmark on Disconnect

**Choice:** Save state in `session$onSessionEnded()` without notification.

**Trade-off:** User cannot be notified (WebSocket closed), but state persists for next session.

## Failed Approaches (DO NOT RETRY)

1. **Manual input restoration via `sendInputMessage()`**: Wrong protocol format. Use Shiny's native restoration with `_state_id_` in URL.

2. **Single redirect after Auth0 callback**: Auth0 codes are single-use. Cannot exchange token then redirect with same code.

3. **Restoring inputs before dynamic UI exists**: Shiny's native restoration handles timing. Manual restoration in `onFlushed` runs before `renderUI` outputs exist.

4. **Checking `isolate(input$x)` for restored value in updateSelectInput observer**: Race condition. By the time the observer runs (with `ignoreInit = FALSE`), `updateSelectInput` overwrites the restored value before it can be read.

## Bookmark Restoration for Dynamic Inputs

**Problem:** Dropdowns with placeholder choices (`selectInput(..., choices = c("No data" = ""))`) that get real choices from DB via `updateSelectInput` don't restore properly. The observer calls `updateSelectInput` with new `selected=` before Shiny's restoration can apply.

**Solution:** "Store and Forward" pattern via `session$userData`:

```r
# server.R - capture ALL input state during onRestore
onRestore(function(state) {
    session$userData$restored_state <- state$input
})

# In any module - use get_restored_input() helper from bookmarks.R
observeEvent(watch("refresh_data"), {
    data <- db_get_data()
    # Priority: shared state > restored bookmark > fallback
    current_val <- as.integer(r$selected_id %||% get_restored_input("input_id"))

    if (purrr::is_empty(data)) {
        updateSelectInput(session, "input_id", choices = c("No data" = ""), selected = "")
    } else {
        choices <- setNames(data$id, data$name)
        selected <- if (isTRUE(current_val %in% data$id)) current_val else data$id[1]
        updateSelectInput(session, "input_id", choices = choices, selected = selected)
    }
}, ignoreInit = FALSE)
```

**Why this works:** `onRestore` runs during session init, before modules are created (which happens after Auth0 gate). The helper `get_restored_input()` (in `shiny-utils/bookmarks.R`) auto-namespaces the input ID and returns NULL for empty values.

## Model Module (300_model)

**Purpose:** Async linear model fitting with save/load functionality.

**Key components:**
- `ExtendedTask` + `mirai` for non-blocking model fitting
- `bslib::input_task_button()` for automatic button state management during async ops
- `butcher::axe_env()` + `axe_fitted()` to minimize model size before storage
- `base::serialize()` to BLOB for robust R object storage (not JSON)

**Why not JSON?** `jsonlite::serializeJSON()` loses environment references. `predict()` fails without manual `.GlobalEnv` fix. `base::serialize()` preserves everything.

**Selective butchering:** Don't use `butcher::butcher()` directly - it removes the `call` component (replaced with `dummy_call()`), breaking `summary()` output. Instead, apply specific axe methods: `axe_env() |> axe_fitted()`. When loading from DB, restore fitted values via `model$fitted.values <- predict(model, newdata = data)`.

**Active page gating:** Expensive operations (DB fetches, deserialization) should only run when user is on the relevant page. Pass `active_page = reactive(input$nav)` to modules and guard with `req(identical(active_page(), "page_id"))`. This prevents wasted work when shared state (like `selected_model_id`) changes while user is on a different page.

---

# Navigation

Uses `bslib::page_navbar()` with shared sidebar. Active tab via `input$nav` (auto-bookmarked).

**Current pattern:** Callback (see global r-shiny.md for alternatives).

```r
# server.R
home_server("home", nav_select_callback = \(page) nav_select("nav", page, session = session))

# Child module
observeEvent(input$click, nav_select_callback("explore"))
```

---

# Auth0 + Bookmarking Integration

## Flow

1. **Outbound**: User visits `/?_state_id_=xyz`. `auth0r::auth0_ui()` encodes bookmark in Auth0's state as `randomState|bookmarkId`.

2. **Callback**: Auth0 redirects with `?code=...&state=randomState|bookmarkId`. State validated via encrypted httpOnly cookie.

3. **URL Cleanup**: `history.replaceState()` removes auth params, preserves `_state_id_`.

4. **Restoration**: Shiny sees `_state_id_`, restores from `shiny_bookmarks/{id}/input.rds`.

5. **Token Exchange**: `auth0r::auth0_server()` populates `session$userData$auth0_info` and `auth0_credentials`.

## Key Components

- `auth0r::auth0_ui()`: OAuth2 flow, CSRF protection, bookmark preservation
- `auth0r::auth0_server()`: Token exchange, logout, excludes auth params from bookmarks
- `auth0r::use_auth0()`: Client-side helpers for URL cleanup

## CSRF Protection

State stored in encrypted httpOnly cookie (sodium). Set `AUTH0_COOKIE_KEY` for production:
```bash
sodium::bin2hex(sodium::random(32))
```

## Email Verification Gate

Modules instantiated only after `session$userData$auth0_info$email_verified`. Unverified users see verification modal.

## Bookmark State ID Format

**Alphanumeric only** (a-zA-Z0-9). Shiny's `RestoreContext` rejects special characters including hyphens.

---

# Session Tracking

## Lifecycle

| Event | Action | Where |
|-------|--------|-------|
| Login | INSERT (ended_at = NULL) | server.R |
| Every 5 min | UPDATE updated_at | server.R (heartbeat) |
| Tab close | UPDATE ended_at, end_reason = 'disconnect' | session$onSessionEnded |
| Every 10 min | Mark stale as 'timeout' | global.R (scheduled) |

## Detection

- **Active**: `ended_at IS NULL AND updated_at > now() - 15 min`
- **Stale/Crashed**: `ended_at IS NULL AND updated_at <= now() - 15 min`
- **Ended**: `ended_at IS NOT NULL`

**Why heartbeat?** `session$onSessionEnded` only fires on graceful disconnects. Crashes/force-closes leave orphan records. 15 min = 3 missed heartbeats = definitely dead.

---

# Logging & Observability

## Application Logging

`R/shiny-utils/logging.R`: `log_info()`, `log_debug()`, `log_error()`. Console (DEBUG in dev, INFO in prod) + JSON files in `logs/` (3-day retention).

## OpenTelemetry

**Local trace viewer** in Admin → Traces (dev only). Config in `.Renviron`:
```bash
OTEL_TRACES_EXPORTER=otelsdk::tracer_provider_memory
OTEL_R_EXPORTER_MEMORY_TRACES_BUFFER_SIZE=5000
```

**Production**: Use external OTLP backend (Grafana, Jaeger, Logfire).

See: https://shiny.posit.co/r/articles/improve/opentelemetry/

---

# Utilities Reference

## Database

- Pool setup: `R/shiny-utils/database.R`
- Schema: `database/schema-base.sql` (users, sessions, bookmarks), `database/schema.sql` (app-specific)
- CRUD: `R/shiny-utils/users.R`, `sessions.R`, `bookmarks.R`; `R/helpers_database.R` (app-specific)

## Scheduler

`R/shiny-utils/scheduler.R`: Tasks self-reschedule via `later`. Tracked by ID, errors logged without stopping. Call `cancel_all_tasks()` in `onStop()`.

## Email

`R/shiny-utils/error_handling.R`: `send_error_email()`, `setup_session_error_emails()`, `setup_global_error_emails()`. Requires `SEND_ERROR_EMAILS=TRUE` and `EMAIL_TO` in .Renviron.

## i18n

Resolution hierarchy: Auth0 `user_metadata.language` → Cookie → Browser preference → App default (`getOption("default_language")`).

## App Loader

Uses `waiter` package for full-page overlay during initialization. `R/shiny-utils/loading.R` provides `is_restore_ready()` for bookmark detection.

Mark `init_state$auth` and `init_state$modules` as TRUE at appropriate points.

---

# Development Notes

## Disabling Auth0

```r
options(auth0_disable = TRUE)
```
Automatically set in test mode.

## Static Asset Cache Busting

```r
tags$script(src = sprintf("js/helpers.js?v=%s", as.integer(Sys.time())))
```

For production, use fixed version or file hash.
