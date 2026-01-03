# Shiny Base

Base template for Shiny apps with Auth0 authentication and server-side bookmarking.

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
│   ├── helpers_*.R       # Non-module functions (includes model DB ops)
│   └── shiny-utils/      # Reusable utilities (git submodule)
│       ├── logging.R, auth0.R, bookmarks.R, caching.R
│       ├── database.R, error_handling.R, i18n.R, loading.R
│       ├── otel.R, sass.R, scheduler.R, sessions.R
│       ├── triggers.R, users.R, utils.R, validation.R
│       ├── permissions.R # RBAC helpers (can, get_user_roles)
│       ├── shinylogs.R   # (Unused) Session replay - see file for schema
│       └── admin/        # Admin dashboard modules (reusable)
│           ├── 900_admin_ui.R, 900_admin_server.R
│           ├── 910_auth0_ui.R, 910_auth0_server.R, 910_auth0_fn.R
│           ├── 912_roles_section_ui.R, 912_roles_section_server.R
│           ├── 920_otel_ui.R, 920_otel_server.R
│           └── 930_system_ui.R, 930_system_server.R, 930_system_fn.R
├── www/                  # Static assets (css/, sass/, js/, html/, img/)
├── data/                 # translations.json, permissions.yaml
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

## Permission Schema

Format: `action:resource` (e.g., `view:admin`, `write:dataset`)

| Verb | Purpose | Example |
|------|---------|---------|
| `view:` | UI access (page/tab/element) | `view:admin`, `view:explore` |
| `write:` | Data modification (create + update) | `write:dataset` |
| `delete:` | Data removal (always separate) | `delete:dataset` |
| `<custom>:` | Domain-specific actions | `fit:model`, `export:report` |

**Wildcards & Denials:**
- `"*"` - All permissions (admin only)
- `"view:*"` - All view permissions
- `"view:admin:*"` - All admin sub-pages
- `"!view:admin:auth0"` - Deny specific permission (overrides wildcards)

## Configuration

Role-permission mapping in `data/permissions.yaml`:

```yaml
roles:
    admin: "*"
    dev:
        - "view:*"
        - "!view:admin:auth0"     # Deny auth0 tab despite view:*
        - "write:dataset"
        - "delete:dataset"
        - "fit:model"
    user:
        - "view:home"
        - "view:explore"
        - "view:model"
        - "write:dataset"
        - "fit:model"             # No admin, no delete
```

## Usage

```r
# Check permission (returns TRUE/FALSE)
can("write:dataset")

# Gate server logic (silent stop if denied)
observeEvent(input$save, {
    req(can("write:dataset"))
    db_save(...)
})

# UI: toggle visibility/state
observe({
    shinyjs::toggle("delete_btn", condition = can("delete:dataset"))
    shinyjs::toggleState("save_btn", condition = can("write:dataset"))
})

# Check actual role if needed
"admin" %in% get_user_roles()
```

## Key Files

- `data/permissions.yaml`: Role-permission mapping (app-specific)
- `R/shiny-utils/permissions.R`: `can()`, `get_user_roles()` (reusable)

## Dev Mode

When `ENV=dev`, all users are treated as admin (bypass for local development).

---

# Admin Panel

Reusable admin dashboard in `R/shiny-utils/admin/`. Provides system monitoring, OTel traces, and user/role management.

## Tabs

| Tab | Module | Purpose |
|-----|--------|---------|
| System | `admin_system_*` | Log viewer with auto-refresh |
| Traces | `admin_otel_*` | OTel trace viewer (dev only, disabled in prod) |
| Users | `admin_auth0_*` | Active sessions, all users, role management |

## Usage

```r
# ui.R
admin_ui(ns("admin"))

# server.R
admin_server("admin", active_page = reactive(input$nav), r = r)
```

## Required Globals

- `auth0_mgmt`: Auth0 Management API client (from auth0r)
- `is_prod`: Boolean for production environment check
- `OTEL_TRACER_PROVIDER`: OTel tracer provider (for traces tab)
- `.ROLE_PERMISSIONS`: Loaded from `data/permissions.yaml`

## Dependencies

Uses functions from shiny-utils:
- `can()`, `get_user_roles()` from permissions.R
- `tr()` from i18n.R (app provides translations)
- `db_get_active_sessions()` from sessions.R
- `db_get_all_users()` from users.R
- `extract_profile_info()` from auth0.R
- `format_relative_time()` from utils.R
- `otel_*` functions from otel.R
- `log_*` functions from logging.R
- `watch()`, `trigger()` from triggers.R

## Translation Keys

App must provide these translation keys:
- Admin Dashboard, System administration and monitoring
- System, Traces, Users, Log Viewer, No log file, Scroll to end, Refresh
- Currently Connected, All Users, Role Management, No active sessions
- Auth0 Roles, App Roles, Create New Role, Role Name, Description (optional)
- Change Role, Save, Cancel, Delete, Create
- just now, %.0f min ago, %.1f hours ago, %.0f days ago
- Connected:, Created:, connections
- Role updated, Role set to user, Role created, Role deleted
- Failed to update role, Failed to create role:, Role name is required

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

# Testing

## Tool Selection

| Use case | Tool |
|----------|------|
| Auth0 flow, multi-page navigation | Playwright |
| Visual regression, UI debugging | Playwright |
| One-off UI checks during development | Playwright (`test:ui` mode) |
| Module reactive logic, internal state | shinytest2 |
| Testing `exportTestValues()` reactives | shinytest2 |
| R package / testthat integration | shinytest2 |

**Playwright** tests what the user sees (DOM). **shinytest2** can access internal Shiny state via `get_values()` and `exportTestValues()`.

## Running the App Locally

```bash
# Port 9090 is required (only callback URL registered in Auth0)
R -e "shiny::runApp(port = 9090)"
```

## Auth0 Bypass

For quick local testing without Auth0 login, set `BYPASS_AUTH0=TRUE`.

## Automated Browser Testing (Playwright)

E2E tests in `tests/e2e/` using `@playwright/test` (official test runner).

**Prerequisites:**
- App running on port 9090
- Dependencies: `npm --prefix tests/e2e install`
- For Auth0 tests: `BYPASS_AUTH0=FALSE` in `.Renviron` (default)

### Running Tests

```bash
# Default: run as dev role
npm --prefix tests/e2e test

# Run as specific role
npm --prefix tests/e2e run test:admin
npm --prefix tests/e2e run test:user

# Run all roles
npm --prefix tests/e2e run test:all

# Interactive UI mode (great for debugging)
npm --prefix tests/e2e run test:ui

# Debug mode (step through tests)
npm --prefix tests/e2e run test:debug

# Show browser window (headless by default)
npm --prefix tests/e2e run test:headed

# Run specific test file
npx --prefix tests/e2e playwright test auth-login.spec.js

# Run specific test by name
npx --prefix tests/e2e playwright test -g "should be authenticated"

# View last test report
npm --prefix tests/e2e run report
```

**Auth0 bypass:** Tests automatically skip Auth0 login if `BYPASS_AUTH0=TRUE` in `.Renviron` or if running in CI (`process.env.CI`).

**CI:** See `.github/workflows/e2e.yml`.

### Writing Tests

Tests use `@playwright/test` with Shiny-specific fixtures:

```js
const { test, expect } = require('./helpers/fixtures');
const { waitForShiny, waitForWaiterHide } = require('./helpers');
const { PAGES, SELECTORS } = require('./app-config');

test.describe('Feature', () => {

    test('example test', async ({ page, shiny }) => {
        await page.goto('/');
        await shiny.waitForReady();  // Wait for Shiny + waiter

        // Built-in Playwright assertions (auto-retry)
        await expect(page.locator('.navbar')).toBeVisible();
        await expect(page.locator('#output')).toHaveText('Expected');

        // Custom Shiny assertions
        await expect(page).toBeOnPage(PAGES.HOME);
        await expect(page).toHaveURLNotContaining('auth0.com');

        // Navigation
        await shiny.navigateTo(PAGES.EXPLORE);
        await expect(page).toBeOnPage(PAGES.EXPLORE);
    });

});
```

### Auth0 Authentication Pattern

Tests use serial mode with a shared browser context to maintain Auth0 sessions:

```js
const { login, getConfig, waitForShiny, waitForWaiterHide } = require('./helpers');

test.describe.configure({ mode: 'serial' });

test.describe('Feature requiring auth', () => {
    let sharedPage;
    const config = getConfig();

    test.beforeAll(async ({ browser }) => {
        const context = await browser.newContext();
        sharedPage = await context.newPage();

        if (!config.bypassAuth0) {
            await login(sharedPage, { role: 'dev' });
        } else {
            await sharedPage.goto(config.targetUrl);
        }
        await waitForShiny(sharedPage);
        await waitForWaiterHide(sharedPage);
    });

    test.afterAll(async () => {
        await sharedPage.context().close();
    });

    test('uses shared page', async () => {
        await expect(sharedPage.locator('.navbar')).toBeVisible();
    });
});
```

**Why this pattern?** Auth0r stores authenticated sessions server-side in R memory, not in browser cookies. Playwright's storage state only captures cookies/localStorage, but the actual session lives in R's session object. Sequential tests reusing the same page avoid re-authentication.

### File Structure

```
tests/e2e/
├── playwright.config.js   # Test runner config (projects per role)
├── global-setup.js        # Ensures app is running
├── app-config.js          # App-specific: PAGES, SELECTORS, flows
├── helpers/
│   ├── fixtures.js        # Playwright Test fixtures + custom matchers
│   ├── index.js           # Unified exports
│   ├── config.js          # .Renviron parsing, ensureAppRunning(), bypassAuth0
│   ├── auth.js            # Auth0 login flow
│   ├── shiny.js           # waitForShiny, waitForReactivity, etc.
│   ├── navigation.js      # navigateTo, getCurrentPage, etc.
│   ├── ui.js              # clickButton, selectDropdown, etc.
│   └── assertions.js      # Legacy assertions (prefer expect())
└── *.spec.js              # Test files
```

### Key Helpers

**Shiny fixture** (available as `shiny` in tests):
- `shiny.waitForReady()` - Wait for Shiny connected + waiter hidden
- `shiny.waitForReactivity(buffer)` - Wait after UI action
- `shiny.navigateTo(page)` - Navigate to navbar page
- `shiny.getCurrentPage()` - Get active page value
- `shiny.getInputValue(id)` - Read Shiny input
- `shiny.setInputValue(id, value)` - Set Shiny input programmatically

**Custom expect matchers:**
- `expect(page).toBeOnPage('explore')` - Assert current navbar page
- `expect(page).toHaveURLNotContaining('auth0.com')` - Assert URL excludes
- `expect(locator).notToBeRecalculating()` - Assert output not recalculating

**Legacy helpers** (still work, but prefer `expect()`):
- `assertText`, `assertVisible`, `assertEnabled`, etc.

**UI helpers:**
- `clickButton(page, id)`, `clickTaskButton(page, id, opts)`
- `fillInput(page, id, value)`, `selectDropdown(page, id, value)`
- `closeModal(page)`, `waitForModal(page)`

### Visual Debugging

```bash
# Interactive mode - see tests run, pause, inspect
npm --prefix tests/e2e run test:ui

# Debug mode - step through with inspector
npm --prefix tests/e2e run test:debug

# Take screenshot mid-test
await page.screenshot({ path: '/tmp/debug.png', fullPage: true });

# Visual regression (saves baseline, compares on reruns)
await expect(page).toHaveScreenshot('modal-open.png');

# View trace after failure
npx playwright show-trace test-results/trace.zip
```

### Projects (Roles)

Config defines 3 projects: `dev`, `admin`, `user`. Each uses different storage state (login session).

Skip tests per role:
```js
test('admin only feature', async ({ page }, testInfo) => {
    if (testInfo.project.name !== 'admin') test.skip();
    // ...
});
```

### Nav Link Selectors

Bslib's navbar creates both tab links and tab panels with `data-value` attributes. Use `.nav-link[data-value="..."]` to target only the link:

```js
// Correct: targets only the nav link
await expect(page.locator('.nav-link[data-value="home"]')).toBeVisible();

// Wrong: matches both link AND panel (strict mode violation)
await expect(page.locator('[data-value="home"]')).toBeVisible();
```

**Stop the app when done:**
```bash
lsof -ti:9090 | xargs kill
```

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
