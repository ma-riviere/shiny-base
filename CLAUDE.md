# Shiny Base

Base template for Shiny apps with Auth0 authentication and server-side bookmarking.

**LLM Resource:** When unsure about Shiny-related issues, consult/brainstorm with the Shiny NotebookLM (skill).

---

# Project Map

## Tech Stack

- **Framework**: Shiny + bslib (Bootstrap 5)
- **Utilities**: `shinyutils` package (private, see `~/dev/projects/R/_packages/shinyutils/CLAUDE.md`)
- **Database**: PostgreSQL (prod) / SQLite (dev/test) via `pool`
- **Auth**: Auth0 via `ma-riviere/auth0r`
- **Email**: `blastula` via Brevo SMTP
- **Observability**: OpenTelemetry (Shiny 1.12+)

## Directory Structure

```
shiny-base/
├── global.R              # App-wide init, options, shinyutils config
├── ui.R                  # Main UI, wraps Auth0, base-level modules
├── server.R              # Main server, module instantiation, bookmarking
├── R/                    # Modules and helpers
│   ├── 00x_*             # Shared sub-modules (navbar, sidebar, dataset_row)
│   ├── 1xx_*             # Home module
│   ├── 2xx_*             # Dataset (Explore) module
│   ├── 3xx_*             # Model module (async fitting via ExtendedTask)
│   └── helpers_*.R       # Non-module functions (includes model DB ops)
├── www/                  # Static assets (css/, sass/, js/, html/, img/)
├── data/                 # translations.json, permissions.yaml
├── database/             # schema-base.sql (users, sessions, bookmarks), schema.sql (app-specific)
├── tests/                # shinytest2, testthat
├── _auth0.yml            # Auth0 configuration
├── .Renviron             # Local dev environment variables
├── .Renviron.prod        # Production environment (secrets, gitignored)
└── shiny_bookmarks/      # Server-side bookmark storage
```

**Note:** Reusable utilities (logging, database, RBAC, admin panel, etc.) are in the `shinyutils` package.

---

# Architecture Decisions

## Auth0 Integration

**Choice:** Custom (private) `ma-riviere/auth0r` instead of `curso-r/auth0`.

**Why:** Native bookmarking support. Encodes `_state_id_` in Auth0's state parameter, keeping redirect URIs clean.

## Bookmark on Disconnect

**Choice:** Save state in `session$onSessionEnded()` without notification.

**Trade-off:** User cannot be notified (WebSocket closed), but state persists for next session.

## Environment Variables Strategy

**Choice:** Single `.Renviron.prod` file for all production config (including secrets) instead of Docker Swarm secrets.

**Why:**
- Simpler mental model: one file for all runtime config
- No Docker secrets infrastructure needed (config.yml → Ansible → Docker secrets → entrypoint script)
- Sufficient security for personal/small-team projects with SSH-key-only access

**Security notes:**
- `.Renviron.prod` is gitignored
- File copied to server with `0640` permissions during Ansible provisioning
- Docker loads via `env_file` directive

**Not for:** Production apps with compliance requirements (use Docker/Kubernetes secrets instead).

## Failed Approaches (DO NOT RETRY)

1. **Manual input restoration via `sendInputMessage()`**: Wrong protocol format. Use Shiny's native restoration with `_state_id_` in URL.

2. **Single redirect after Auth0 callback**: Auth0 codes are single-use. Cannot exchange token then redirect with same code.

3. **Restoring inputs before dynamic UI exists**: Shiny's native restoration handles timing. Manual restoration in `onFlushed` runs before `renderUI` outputs exist.

4. **Checking `isolate(input$x)` for restored value in updateSelectInput observer**: Race condition. By the time the observer runs (with `ignoreInit = FALSE`), `updateSelectInput` overwrites the restored value before it can be read.

5. **Using `req()` or `req(can())` at top level of `moduleServer()`**: Silent errors thrown by `req(FALSE)` propagate up when called outside reactive contexts, crashing `init_modules()` before `init_state` flags are set. Use `if (!can(...)) return()` instead.

6. **Using `purrr::pluck(session, "userData", ...)` inside modules**: `pluck` bypasses `SessionProxy`'s `$` dispatch that delegates to the parent session. Use `session$userData$...` instead.

7. **Playwright storage state for Auth0 session persistence**: Auth0r stores sessions server-side in R memory, not in browser cookies. The `auth0_state` cookie is a one-time CSRF token consumed during OAuth callback, not a session cookie. Use serial mode with shared page and login-per-describe instead.

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

**Why this works:** `onRestore` runs during session init, before modules are created (which happens after Auth0 gate). The helper `get_restored_input()` (from `shinyutils`) auto-namespaces the input ID and returns NULL for empty values.

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
home_server("home", nav_select_callback = \(page) nav_select("nav", page))

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

# Role-Based Access Control (RBAC)

Uses `shinyutils::can()` and `shinyutils::get_user_roles()`. See shinyutils CLAUDE.md for full documentation.

## App-Specific Configuration

Role-permission mapping in `data/permissions.yaml`:

```yaml
roles:
    admin: "*"
    dev:
        - "view:*"
        - "!view:admin:auth0"
        - "write:dataset"
        - "delete:dataset"
        - "fit:model"
    user:
        - "view:home"
        - "view:explore"
        - "view:model"
        - "write:dataset"
        - "fit:model"
```


---

# Admin Panel

Uses `shinyutils::admin_ui()` and `shinyutils::admin_server()`. See shinyutils for full documentation.

## Usage

```r
# ui.R
admin_ui(ns("admin"))

# server.R
admin_server("admin", active_page = reactive(input$nav))
```

## Translation Keys

Admin panel translations are bundled in `shinyutils` (`inst/translations.json`).
App-specific translations go in `data/translations.json`. App translations override
package translations for duplicate keys.

---

# Session Tracking

Uses `shinyutils` session functions. See shinyutils CLAUDE.md for lifecycle details.

## App Integration (server.R)

| Event | Call |
|-------|------|
| Login | `db_session_start(user_id, session_id)` |
| Every 5 min | `db_session_heartbeat(session_id)` |
| Tab close | `db_session_end(session_id, "disconnect")` |

Scheduled cleanup in global.R: `schedule_task("session_cleanup", session_cleanup, interval_seconds = 600)`

---

# Logging & Observability

Uses `shinyutils` logging functions. See shinyutils CLAUDE.md for details.

## App Configuration

Logging options in global.R:
- `log_dir`: Directory for log files (default: "logs")
- `log_console_threshold`: Console verbosity (LOG_DEBUG in dev, LOG_INFO in prod)
- `log_file_threshold`: File verbosity (LOG_DEBUG)

## OpenTelemetry

Config in `.Renviron`:
```bash
OTEL_TRACES_EXPORTER=otelsdk::tracer_provider_memory
OTEL_R_EXPORTER_MEMORY_TRACES_BUFFER_SIZE=5000
```

Local trace viewer in Admin → Traces (dev only). Production: use external OTLP backend.

See: https://shiny.posit.co/r/articles/improve/opentelemetry/

---

# Utilities Reference

All utilities are in the `shinyutils` package. See shinyutils CLAUDE.md for full API.

## App-Specific Files

- **Schema**: `database/schema-base.sql` (users, sessions, bookmarks), `database/schema.sql` (app tables)
- **App CRUD**: `R/helpers_database.R` (dataset/model operations)
- **Translations**: `data/translations.json`
- **Permissions**: `data/permissions.yaml`

## i18n

Resolution hierarchy: Auth0 `user_metadata.language` → Cookie → Browser preference → App default.

## App Loader

Uses `waiter` package for full-page overlay. Mark `init_state$auth` and `init_state$modules` as TRUE at appropriate points.

---

# Testing

See global `~/.claude/rules/shiny-tests.md` for general Shiny/Playwright testing patterns.

## Project-Specific

**Port:** 9090 (only callback URL registered in Auth0).

```bash
R -e "shiny::runApp(port = 9090)"
```

**Roles:** Config defines 3 projects: `dev`, `admin`, `user`.

**CI:** `.github/workflows/e2e.yml`

**App config:** `tests/e2e/app-config.js` defines PAGES and SELECTORS for this app.
**Key Tests:**
- `workflow-dataset-model.spec.js`: E2E workflow testing dataset upload, model fitting, saving, and deletion.
- Run: `npm run test:workflow`
 
# Development Notes

## Disabling Auth0

```r
options(auth0_disable = TRUE)
```
Automatically set in test mode.

## Static Asset Cache Busting

```r
tags$script(src = sprintf("js/app.js?v=%s", as.integer(Sys.time())))
```

For production, use fixed version or file hash.
