# Shiny Base

Base template for Shiny apps with Auth0 authentication and server-side bookmarking.

**Auth0 credentials:** `ma.riviere987@gmail.com` / `auth0test&15`

**LLM Resource:** When unsure about Shiny-related issues, consult/brainstorm with the Shiny NotebookLM (skill) - a domain expert with up-to-date documentation, code examples, books, and tutorials.

---

# Project Map

## Tech Stack

- **Framework**: Shiny with `bslib` for Bootstrap 5 UI
- **Database**: PostgreSQL (prod) / SQLite (dev/test) via `pool` package
- **Auth**: Auth0 via `ma-riviere/auth0r` package
- **i18n**: `shiny.i18n` for translations (EN/FR)
- **Email**: `blastula` via Brevo SMTP
- **Styling**: SASS compiled to CSS

## Directory Structure

```
shiny-base/
├── global.R              # App-wide initialization, options, database pool
├── ui.R                  # Main UI, wraps Auth0, loads base-level modules
├── server.R              # Main server logic, module instantiation, bookmarking
├── R/                    # All modules and helpers
│   ├── 00x_*_ui/server.R # Shared sub-modules (navbar, sidebar, dataset_row, etc.)
│   ├── x00_*_ui/server.R # Base-level page modules (home, dataset)
│   ├── helpers_*.R       # Non-module helper functions
│   └── shiny-utils/      # Reusable utilities (git submodule)
│       ├── 000_logging.R # Structured logging
│       ├── caching.R     # Cache utilities
│       ├── database.R    # DB connection pool management
│       ├── error_handling.R
│       ├── i18n.R        # Language resolution
│       ├── sass.R        # SASS compilation
│       ├── scheduler.R   # Recurring task scheduler (uses `later`)
│       ├── triggers.R    # Event broadcast system
│       └── validation.R  # Custom shinyvalidate rules
├── www/                  # Static assets
│   ├── css/              # Compiled CSS (main.min.css)
│   ├── sass/             # SCSS source files
│   │   ├── main.scss     # Entry point
│   │   ├── variables.scss
│   │   ├── navbar.scss, typo.scss
│   │   └── _*.scss       # Partials (buttons, cards, layout, modals, tables, utils)
│   ├── js/               # JavaScript helpers
│   ├── html/             # HTML templates (for htmltools::htmlTemplate)
│   └── img/              # Images
├── data/                 # Data files (translations.json)
├── database/             # DB schema/migrations
├── tests/                # shinytest2, testthat tests
├── renv/                 # renv configuration
│   └── profiles/         # dev-4.5, docker-4.5
├── _auth0.yml            # Auth0 configuration
├── .Renviron             # Environment variables (API keys, etc.)
└── shiny_bookmarks/      # Server-side bookmark storage
```

## Entry Points

- **Run app**: `shiny::runApp(launch.browser = FALSE)` from project root
- **Compile SASS**: Source `R/shiny-utils/sass.R`. Done automatically on app launch.

---

# Architecture Decisions

## Auth0 Integration (auth0r package)

**Choice:** Use custom `ma-riviere/auth0r` fork instead of `curso-r/auth0`.

**Why:** Native bookmarking support. The fork encodes `_state_id_` in Auth0's state parameter, keeping redirect URIs clean and enabling seamless bookmark restoration after login.

## Event System (Triggers)

**Choice:** Gargoyle-style trigger system for cross-module communication.

**Trade-off:** Escapes Shiny's reactive graph, making data flow harder to trace. Acceptable for app-wide events with single handlers (e.g., `refresh_datasets`).

**Alternative considered:** Callback prop-drilling (current for navigation). Works for shallow hierarchies but becomes painful at 3+ levels.

## Explicit Event Handling

**Preference:** Always make reactive dependencies explicit. Avoid bare `observe()` with implicit dependencies.

| Pattern | When to use |
|---------|-------------|
| `on("trigger", { ... })` | React only when triggered (default: `ignoreInit = TRUE`) |
| `observeEvent(x(), { ... })` | React to a single reactive |
| `observeEvent(list(watch("trigger"), x()), { ... })` | React to trigger AND other reactives |
| `observe({ ... }) \|> bindEvent(x())` | Same as `observeEvent`, alternative syntax |
| `observe({ req(...); ... })` | One-time initialization waiting for state |

**Why:** Implicit dependencies in `observe()` make data flow hard to trace. Explicit event expressions
document intent and prevent accidental dependencies.

**Triggers are events, not state:** `on()` defaults to `ignoreInit = TRUE` because triggers are
imperative signals ("do this now"), not state synchronization.

## Input Rate Limiting (Debounce/Throttle)

Two approaches exist for rate-limiting high-frequency inputs (sliders, text fields):

| Approach | Location | Network Traffic | Use When |
|----------|----------|-----------------|----------|
| `data-shiny-input-rate-policy` | Client (browser) | Low - only sends settled values | Single input, bandwidth concerns |
| `debounce()` / `throttle()` | Server (R) | High - sends all values, debounces in R | Multiple inputs, dynamic delays |

**Prefer client-side rate policy** for individual inputs like sliders:

```r
sliderInput("filter", "Filter", min = 0, max = 100, value = 50) |>
    tagAppendAttributes(
        `data-shiny-input-rate-policy` = '{"policy": "debounce", "delay": 300}'
    )
```

**Prefer server-side `debounce()`** when:
- Debouncing a combination of multiple inputs into one reactive
- Debouncing non-input reactives (database polls, computed values)
- Need dynamic delay based on other reactive values

```r
# Server-side: debounce a reactive that combines multiple inputs
filters <- reactive(list(input$a, input$b, input$c)) |> debounce(500)
```

## Dynamic Module Instantiation

**Choice:** "Initialize once, render many" pattern with `lapply` or `purrr::map` (not `for` loops).

**Why:** Avoids duplicate observers on re-render. `lapply` creates new environments per iteration, preventing lazy evaluation traps where all modules capture the final loop value.

## Bookmark on Disconnect

**Choice:** Save input state in `session$onSessionEnded()` without user notification.

**Trade-off:** User cannot be notified (WebSocket already closed), but state is persisted for next session.

## Failed Approaches (DO NOT RETRY)

1. **Manual input restoration via `sendInputMessage()`**: Wrong protocol format. Use Shiny's native restoration with `_state_id_` in URL instead.

2. **Single redirect after Auth0 callback**: Auth0 codes are single-use. Cannot exchange token then redirect with same code.

3. **`for` loops for module initialization**: Lazy evaluation trap. All modules see final loop value.

---

## Navigation

The app uses `bslib::page_navbar()` for navigation with a shared sidebar across all pages.
- Navigation tabs are defined as `bslib::nav_panel()` elements
- The active tab is tracked via `input$nav` (automatically bookmarked by Shiny)
- Use `bslib::nav_select("nav", "page_value", session = session)` to programmatically switch tabs

### Cross-Module Navigation Patterns

When a child module needs to trigger navigation (e.g., clicking a dataset row navigates to
the dataset page), there are three approaches. Choose based on app complexity.

#### Pattern Comparison

| Approach | Coupling | Debugging | Scalability | Use When |
|----------|----------|-----------|-------------|----------|
| Callback | Medium | Easy | Low (prop-drilling) | Small apps, shallow hierarchy |
| Triggers | Low | Hard (hidden logic) | High | Large apps, sibling communication |
| Reactive Return | High | Easy (explicit graph) | Medium | Need testability with `testServer()` |
| Shared reactiveValues | Low | Easy (explicit graph) | High | Sibling modules sharing mutable state |

#### 1. Callback Function (Current Pattern)

Parent defines a navigation helper and passes it to child modules.

```r
# server.R
home_server(
    "home",
    nav_select_callback = \(page) bslib::nav_select("nav", page, session = session)
)

# R/100_home_server.R
home_server <- function(id, nav_select_callback = NULL) {
    moduleServer(id, function(input, output, session) {
        observeEvent(input$dataset_click, {
            if (!is.null(nav_select_callback)) {
                nav_select_callback("dataset")
            }
        })
    })
}
```

**Pros:** Child stays decoupled from parent's navbar ID. Simple, explicit.

**Cons:** "Prop drilling" - deeply nested modules require passing callback through every layer.

#### 2. Triggers (gargoyle-style)

Uses the event system from `R/shiny-utils/triggers.R`. Navigation becomes a broadcast event.

```r
# server.R
init("nav_to_dataset", "nav_to_home")
on("nav_to_dataset", { nav_select("nav", "dataset") })
on("nav_to_home", { nav_select("nav", "home") })

# R/100_home_server.R (no callback parameter needed)
observeEvent(input$dataset_click, {
    trigger("nav_to_dataset")
})
```

**Pros:** Completely decouples modules. Sibling modules can trigger navigation without any
direct link. No prop drilling regardless of nesting depth.

**Cons:** "Escapes the reactive graph" - navigation logic is hidden from Shiny's dependency
tracking. Harder to reason about data flow. Multiple listeners react to same trigger.

#### 3. Reactive Return Values

Child module returns an `eventReactive` signaling the target tab. Parent observes and navigates.

```r
# R/100_home_server.R
home_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        nav_target <- eventReactive(input$dataset_click, { "dataset" })
        return(list(nav_to = nav_target))
    })
}

# server.R
home_module <- home_server("home")
observeEvent(home_module$nav_to(), {
    req(home_module$nav_to())
    nav_select("nav", home_module$nav_to())
})
```

**Pros:** Most "Shiny-native". Explicit reactive graph. Testable with `testServer()`.

**Cons:** More verbose. Each module needs return value handling in parent. Managing multiple
navigation targets requires returning a list of reactives.

#### When to Switch Patterns

**Keep callbacks** (current) when:
- App has < 5 modules at 1-2 levels of nesting
- No need for `testServer()` on navigation logic
- Navigation is always parent-child (not sibling-to-sibling)

**Switch to triggers** when:
- App grows to 10+ modules
- Sibling modules need to trigger each other's navigation
- Deep nesting makes prop drilling painful
- You accept the trade-off of hidden control flow

**Switch to reactive returns** when:
- You need to test navigation logic with `testServer()`
- You want the reactive graph to be fully explicit
- You're willing to add boilerplate in parent for each module

#### Migration Path

If starting with callbacks and app grows complex:

1. First, consider if triggers are appropriate for the specific navigation needs
2. Define scoped trigger names: `nav_to_home`, `nav_to_dataset` (not generic `navigate`)
3. Register handlers once in `server.R`, not in modules
4. Remove callback parameters from module signatures
5. Replace `nav_select_callback("dataset")` with `trigger("nav_to_dataset")`

#### 4. Shared reactiveValues ("Petit r" pattern) — Current for State

When **sibling modules** need to both **read and write** the same state (not just navigation),
create a shared `reactiveValues` in the parent and pass it to both modules.

```r
# server.R - parent creates shared state
init_modules <- function() {
    r <- reactiveValues(
        selected_dataset_id = NULL
    )

    sidebar_server("sidebar", r = r)  # Reads and writes r$selected_dataset_id
    home_server("home", r = r)        # Writes r$selected_dataset_id on row click
    dataset_server("dataset",
        selected_dataset_id = reactive(r$selected_dataset_id)  # Reads via reactive
    )
}

# sidebar_server.R - bidirectional sync with r
sidebar_server <- function(id, r) {  # r is required, not optional
    moduleServer(id, function(input, output, session) {
        # Sync FROM shared state (when home page sets r$selected_dataset_id)
        observeEvent(r$selected_dataset_id, {
            req(r$selected_dataset_id)
            updateSelectInput(session, "selected_dataset",
                selected = as.character(r$selected_dataset_id))
        }, ignoreNULL = TRUE, ignoreInit = TRUE)

        # Sync TO shared state (when user changes dropdown)
        observeEvent(input$selected_dataset, {
            r$selected_dataset_id <- as.integer(input$selected_dataset)
        })
    })
}

# home_server.R - writes to r on user action
home_server <- function(id, r) {
    moduleServer(id, function(input, output, session) {
        on_click <- \(dataset_id) {
            r$selected_dataset_id <- dataset_id
        }
    })
}
```

**Pros:** Natively reactive (no manual sync checks). Explicit dependencies via function signature.
Testable with `testServer()`. No hidden globals or namespace collision.

**Cons:** Requires passing `r` to all modules that need it. State is mutable from multiple places.

**Make `r` required, not optional:**
```r
# GOOD: Explicit dependency, fails fast if missing
sidebar_server <- function(id, r) { ... }

# BAD: Hidden dependency, defensive checks everywhere
sidebar_server <- function(id, r = NULL) {
    if (!is.null(r)) r$selected_dataset_id <- ...  # Noise
}
```

**When to use "Petit r" over triggers:**
- Triggers are for *events* (no payload): "refresh now", "show modal"
- Shared `r` is for *state* (data flow): selected ID, filter values
- If you catch yourself writing `session$userData$some_value` + `trigger("value_changed")`,
  refactor to shared `reactiveValues` instead

## Dynamic Module Instantiation

When rendering a list of items where each item is a Shiny module (e.g., dataset rows), you must
avoid calling `moduleServer()` inside `renderUI()`. Each re-render would create duplicate
observers, causing memory leaks and multiple event handlers firing.

### Anti-Pattern (DO NOT DO THIS)

```r
output$item_list <- renderUI({
    items <- filtered_items()
    lapply(seq_len(nrow(items)), \(i) {
        row <- items[i, ]
        # BAD: Creates new observers on every re-render
        item_row_server(paste0("row_", row$id), dataset = reactive(row))
        item_row_ui(ns(paste0("row_", row$id)))
    }) |> tagList()
})
```

### Solution: "Initialize Once, Render Many"

Separate server initialization (once per unique ID) from UI rendering (can repeat safely).

```r
module_server <- function(id, ...) {
    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Cache of initialized row module IDs
        loaded_row_ids <- reactiveVal(character(0))

        # 1. Initialize module servers ONCE per new ID
        observeEvent(all_items(), {
            current_ids <- paste0("row_", all_items()$id)
            new_ids <- setdiff(current_ids, loaded_row_ids())

            # IMPORTANT: Use lapply, NOT for loop (lazy evaluation trap)
            lapply(new_ids, \(rid) {
                numeric_id <- as.integer(sub("row_", "", rid))
                item_row_server(
                    rid,
                    all_items = all_items,
                    row_id = reactive({ numeric_id })  # Always pass as reactive
                )
            })
            loaded_row_ids(union(loaded_row_ids(), new_ids))
        })

        # 2. Render UI (safe to repeat - just generates HTML)
        output$item_list <- renderUI({
            items <- filtered_items()
            lapply(seq_len(nrow(items)), \(i) {
                item_row_ui(ns(paste0("row_", items$id[i])))
            }) |> tagList()
        })
    })
}
```

### Critical: Avoid the Lazy Evaluation Trap

**Never use `for` loops** to initialize modules with captured variables:

```r
# BAD: All modules see the LAST value of numeric_id
for (rid in new_ids) {
    numeric_id <- as.integer(sub("row_", "", rid))
    item_row_server(rid, row_id = reactive({ numeric_id }))  # All get same ID!
}

# GOOD: lapply creates new environment per iteration, freezing each value
lapply(new_ids, \(rid) {
    numeric_id <- as.integer(sub("row_", "", rid))
    item_row_server(rid, row_id = reactive({ numeric_id }))  # Each gets correct ID
})
```

R's `for` loops reuse the same environment. By the time reactives execute, they look up the
variable and find its final value. `lapply` creates a new function environment per iteration.

### Always Use Reactive for row_id

For consistency, **always pass `row_id` as a reactive**, even for static IDs:

```r
# Parent (static ID case - e.g., list of items)
row_id = reactive({ numeric_id })

# Parent (dynamic ID case - e.g., selected item can change)
row_id = reactive({ values$selected_id })

# Child module - always call as reactive
my_data <- reactive({
    rid <- row_id()
    req(rid)
    # ...
})
```

This avoids dual-mode logic in the child module and makes the API consistent.

### Logic Gating with req()

Inside the child module, use `req()` to pause logic when the item is deleted. This prevents
errors without needing manual observer cleanup.

```r
item_row_server <- function(id, all_items, row_id) {
    moduleServer(id, function(input, output, session) {
        # Gate: pauses all downstream logic if this row no longer exists
        my_data <- reactive({
            data <- all_items()
            rid <- row_id()
            req(rid)
            req(rid %in% data$id)
            data[data$id == rid, ]
        })

        # All observers/outputs use my_data() - they'll silently pause if row is gone
        output$name <- renderText({ my_data()$name })

        observeEvent(input$delete, {
            req(my_data())  # Double-check before destructive action
            # ... delete logic
        })
    })
}
```

### Key Points

1. **Use persistent IDs**, not row indices (1, 2, 3). Database IDs are ideal.
2. **Use `lapply`**, not `for` loops, to avoid lazy evaluation trap.
3. **Always pass `row_id` as reactive** for consistent API.
4. **Pass the full reactive**, not sliced data. Let the child module filter for its own row.
5. **Modules stay in memory** for the session but are "paused" when their data disappears.
6. **No manual cleanup needed** - `req()` gating is sufficient for most use cases.

### Memory Considerations (Zombie Observers)

When a row is deleted, its module's observers remain in memory (Shiny has no "destroy module"
function). The `req()` gating effectively pauses them, preventing CPU usage.

**This is acceptable when:**
- Typical usage involves < 100 dynamic modules per session
- Users don't repeatedly create/delete thousands of items

**Consider alternatives when:**
- High-churn scenarios (thousands of creates/deletes per session)
- Heavy modules with large state or many observers
- Memory profiling shows issues

### renderUI vs insertUI/removeUI

The current pattern uses `renderUI` which regenerates all HTML on each change. This is
acceptable for read-only displays but has trade-offs:

| Approach | Pros | Cons |
|----------|------|------|
| `renderUI` | Simple, familiar | Resets input state, regenerates all HTML |
| `insertUI/removeUI` | Preserves siblings, surgical updates | More complex, "zombie inputs" persist |

**Stick with `renderUI` when:**
- Rows are read-only (no inputs to preserve)
- List is small (< 50 items)
- Simplicity is preferred

**Consider `insertUI/removeUI` when:**
- Rows contain user inputs that must preserve state
- Performance issues with large lists
- Need surgical add/remove without affecting siblings

### When Strict Cleanup is Needed

For heavy modules (large state, many observers), you can track observer handles and call
`$destroy()`. This is rarely necessary:

```r
# Inside module: name observers with pattern
delete_observer <- observeEvent(input$delete, { ... })

# Expose a cleanup function
return(list(
    destroy = function() {
        delete_observer$destroy()
        # ... destroy other observers
    }
))

# Parent tracks and cleans up
module_instances <- list()
observeEvent(all_items(), {
    ids_to_remove <- setdiff(names(module_instances), current_ids)
    for (id in ids_to_remove) {
        module_instances[[id]]$destroy()
        module_instances[[id]] <- NULL
    }
})
```

## Auth0 + Bookmarking Integration

The app uses `ma-riviere/auth0r` for Auth0 authentication with built-in bookmark preservation.
Unlike the standard `curso-r/auth0` package, auth0r handles server-side bookmarking correctly by
encoding `_state_id_` in Auth0's state parameter, keeping the redirect URI clean.

### How it works

1. **Outbound**: User visits `/?_state_id_=xyz`. `auth0r::auth0_ui()` encodes the bookmark ID
   in Auth0's state param as `randomState|bookmarkId`, redirects to Auth0 with a clean redirect_uri.

2. **Auth0 Callback**: Auth0 redirects back with `?code=...&state=randomState|bookmarkId`.
   `auth0r::auth0_ui()` validates state via encrypted httpOnly cookie (CSRF protection).

3. **URL Cleanup**: `auth0r::auth0_ui()` injects `history.replaceState()` to clean auth params
   from the URL while preserving `_state_id_` for bookmark restoration.

4. **Native Restoration**: Shiny sees `_state_id_` in the URL and automatically restores all
   inputs from `shiny_bookmarks/{id}/input.rds`. This includes the active tab (`input$nav`)
   which `bslib::page_navbar()` handles automatically.

5. **Token Exchange**: `auth0r::auth0_server()` exchanges the auth code for tokens and populates
   `session$userData$auth0_info` and `session$userData$auth0_credentials`.

### Key components

- `auth0r::auth0_ui()`: Handles OAuth2 flow, CSRF protection, bookmark preservation
- `auth0r::auth0_server()`: Token exchange, logout handler, excludes auth params from bookmarks
- `www/js/helpers-auth0.js`: Detects fresh login vs page refresh for bookmark restoration offer

### CSRF Protection

auth0r uses encrypted httpOnly cookies (via sodium) to protect against CSRF attacks:
- State is generated per-request and stored encrypted in a cookie before redirecting to Auth0
- On callback, the state from the URL is validated against the decrypted cookie
- Set `AUTH0_COOKIE_KEY` env var for production (generate with `sodium::bin2hex(sodium::random(32))`)

### Email verification gate

Modules are only instantiated after verifying `session$userData$auth0_info$email_verified`.
Unverified users see a modal prompting them to verify their email.

### Excluded inputs

Some inputs must be excluded from bookmarking via `setBookmarkExclude()` in `server.R`.

**Always exclude:**

1. **Action buttons that trigger side effects**: Any `observeEvent(input$btn, ...)` that triggers
   modals, API calls, file uploads, database writes, or navigation. Shiny restores button click
   counts, causing the handler to fire immediately on restore.

2. **File inputs**: Restored metadata references temp files that no longer exist.

3. **Inputs inside modals**: Modal content is transient and shouldn't persist. Restoring these
   inputs is pointless (modal isn't open) and can cause errors.

4. **Confirmation/delete buttons**: Especially dangerous - restoring a delete confirmation could
   trigger data loss.

**Safe to bookmark (don't exclude):**

- Dropdowns, sliders, text inputs that filter/display data (no side effects)
- Navigation state (`input$nav` - handled automatically by bslib)
- Toggle switches that control UI visibility

**Testing new inputs**: Save a bookmark after interacting with the input, then restore. If
unwanted behavior occurs (modal opens, action fires, error thrown), add to `setBookmarkExclude()`.

### Bookmark on disconnect

When a user disconnects (closes tab, loses internet, etc.), `session$onSessionEnded()` saves
the current input state as a bookmark. This happens server-side after the WebSocket closes,
so the user cannot be notified, but the state is persisted for their next session.

- Implementation: `save_bookmark_on_disconnect()` in `R/helpers_bookmarks.R`
- Uses `isolate(reactiveValuesToList(input))` since no reactive context is available
- Manually creates `shiny_bookmarks/{id}/input.rds` (same format as native bookmarking)
- Registers bookmark in DB for the restore-on-login flow
- Does NOT delete previous bookmarks (unlike explicit saves) to avoid race conditions

**Important**: State IDs must be alphanumeric only (a-zA-Z0-9). Shiny's `RestoreContext`
validates with `grepl("[^a-zA-Z0-9]", id)` and rejects any special characters including
hyphens.

### Bookmark restoration offer

On fresh login (not page refresh), the app checks for a recent bookmark (<30 min old) and
offers to restore it via a toast notification. This uses `input$session_status` set by
`www/js/helpers-auth0.js` based on sessionStorage.

### Pitfalls and failed approaches

**DO NOT try these approaches - they don't work in this context:**

1. **Manual input restoration via `sendInputMessage()`**: Does not work. The message format
   `list(value = value)` is not the correct protocol for Shiny inputs. The `update*()` functions
   handle the correct format internally, but calling them for every input type is complex.
   **Solution**: Use Shiny's native restoration by ensuring `_state_id_` is in the URL.

2. **Restoring inputs before dynamic UI exists**: Shiny's native restoration handles timing
   correctly. Manual restoration in `onFlushed` callbacks runs before `renderUI` outputs exist.

3. **Single redirect after Auth0 callback**: Auth0 codes are single-use. You cannot exchange
   the code for tokens and then redirect to a different URL with the same code.
   **Solution**: Redirect in the UI layer (before server runs) to add `_state_id_` while
   keeping the original `code` and `state` params.

## Event Triggers

`R/shiny-utils/triggers.R` provides a lightweight event system for cross-module communication,
inspired by the `gargoyle` package. Triggers are stored in `session$userData` and act as
**broadcast events** - any module can fire them, and all listeners react.

### API

```r
init("refresh_datasets", "show_upload_modal")  # Call once in server.R
trigger("refresh_datasets")                     # Fire from any module
watch("refresh_datasets")                       # Create reactive dependency in observe/reactive
on("show_upload_modal", { showModal(...) })     # React to trigger (wrapper around observeEvent)
```

### Key principle: triggers are broadcasts

Unlike reactive parameters (which are point-to-point), triggers broadcast to **all** listeners.
If two modules both call `on("show_upload_modal", ...)`, both will fire when triggered.

### Best practices

1. **App-wide events with single handler**: Use for events where exactly one module should react.
   - `refresh_datasets` - sidebar refreshes dropdown
   - `show_upload_modal` - single upload module shows modal

2. **Shared modules belong at app level**: If multiple pages need the same functionality (e.g.,
   upload modal), instantiate the module once in `server.R`, not in each page module.

3. **Scoped naming for multiple instances**: If you need independent instances of the same
   behavior, use scoped trigger names:
   - `show_modal_home`, `show_modal_dataset` (instead of generic `show_modal`)

### Triggers vs reactive parameters: when to use which

**Triggers** are for **events/signals** (no payload). **Reactive parameters** are for **data flow**.

| Use Case | Correct Approach |
|----------|------------------|
| Filter values (date range, row count) | Reactive parameters |
| Selected item ID | Reactive parameters |
| "Database updated, refresh UI" | Trigger |
| "Show upload modal" | Trigger |

**Anti-pattern: triggers for data flow**

```r
# WRONG: Using triggers + session$userData for filter values
observeEvent(input$row_count, {
    session$userData$row_count_filter <- input$row_count
    trigger("filters_changed")
})

# Consumer has hidden dependency on session$userData structure
on("filters_changed", {
    filter_data(session$userData$row_count_filter)  # Where does this come from?
})
```

**Problems:** Hidden dependencies, untestable with `testServer()`, namespace collision risk.

**Correct: reactive parameters for data flow**

```r
# Sidebar module returns filter values
sidebar_server <- function(id) {
    moduleServer(id, function(input, output, session) {
        return(list(
            row_count_filter = reactive(input$row_count),
            age_filter = reactive(input$age)
        ))
    })
}

# Parent captures and passes to siblings - explicit dependencies
sidebar_module <- sidebar_server("sidebar")
home_server("home",
    row_count_filter = reactive(sidebar_module$row_count_filter()),
    age_filter = reactive(sidebar_module$age_filter())
)
```

**Rule of thumb:** If you're passing *data*, use reactive parameters. If you're saying
*"something happened, react to it"* without caring about payload, use triggers.

### Debugging

Enable verbose logging to see trigger activity:
```r
options(triggers.verbose = TRUE)
```

## Email

The app uses `blastula` for sending emails via SMTP (configured for Brevo).

### Configuration

Environment variables (in `.Renviron`):
- `EMAIL_TO`: Default recipient email address
- `EMAIL_FROM`: Sender email address
- `SMTP_HOST`: SMTP server (e.g., `smtp-relay.brevo.com`)
- `SMTP_PORT`: SMTP port (default: 587)
- `SMTP_USER`: SMTP username/login
- `SMTP_KEY`: SMTP API key/password

Options (set in `global.R`):
- `email_to`, `email_from`, `smtp_host`, `smtp_port`, `smtp_user`: Read from env vars
- `smtp_key_envvar`: Name of env var holding SMTP key (default: `"SMTP_KEY"`)
- `error_email_enabled`: Whether to send emails on unhandled errors (controlled by `SEND_ERROR_EMAILS` env var, default: `FALSE`)

### Error notification emails

`R/shiny-utils/error_handling.R` provides automatic error notification:
- `send_error_email(error_msg, session)`: Sends error details with context (user, R version, stack trace)
- `setup_error_handlers(session)`: Registers session-level error handlers (call in `server.R`)
- `setup_global_error_handlers()`: Sets up global error handling (called in `global.R`)

Error emails are only sent when `SEND_ERROR_EMAILS=TRUE` and `EMAIL_TO` is configured.

### Sending custom emails

```r
email <- blastula::compose_email(
    body = blastula::md("Your **markdown** content here")
)

blastula::smtp_send(
    email = email,
    to = "recipient@example.com",
    from = getOption("email_from"),
    subject = "Subject line",
    credentials = blastula::creds_envvar(
        user = getOption("smtp_user"),
        pass_envvar = getOption("smtp_key_envvar"),
        host = getOption("smtp_host"),
        port = getOption("smtp_port"),
        use_ssl = TRUE
    )
)
```

## Database

The app uses a PostgreSQL database with connection pooling (`pool` package).
- Connection setup in `R/shiny-utils/database.R`, CRUD functions in `R/helpers_database.R`
- Pool created in `global.R`, closed via `onStop()` callback
- Bookmark tracking: stores user bookmarks in DB, cleans up old ones on save

## Scheduler

The app uses `R/shiny-utils/scheduler.R` for recurring background tasks via the `later` package.

### API

```r
# Schedule a recurring task (replaces existing task with same ID)
schedule_task("bookmark_cleanup", bookmark_cleanup, interval_seconds = 30 * 60)

# Cancel a specific task
cancel_task("bookmark_cleanup")

# Cancel all tasks (call in onStop())
cancel_all_tasks()

# List active task IDs
list_tasks()
```

### How it works

- Tasks self-reschedule after each execution
- Errors are caught and logged without stopping the schedule
- Tasks are tracked by ID, allowing replacement of existing tasks
- `cancel_all_tasks()` is called in `onStop()` for clean shutdown

### Current scheduled tasks

| Task ID | Function | Interval | Purpose |
|---------|----------|----------|---------|
| `bookmark_cleanup` | `bookmark_cleanup()` | 30 min | Delete expired bookmarks and orphaned folders |

**Note:** `logs_cleanup()` runs once on startup only (not scheduled) since log files are only created when the app starts.

## i18n (Internationalization)

Uses `shiny.i18n` for translations. Language resolution hierarchy:
1. Auth0 `user_metadata.language` (source of truth for authenticated users)
2. Cookie (name from `getOption("language_cookie_name")`, 1-year expiry)
3. Browser language preference
4. App default (from `getOption("default_language")`)

### Important: Update translations when UI changes

**ALWAYS update `data/translations.json` when adding or modifying UI text elements.** This includes:
- New button labels, modal titles, form labels
- Toast notifications, error messages
- Any user-facing text marked with `tr()` or `class="i18n"`

The translations file contains both English and French entries. When adding new text:
1. Add the English entry
2. Add the corresponding French translation (use a translation tool if needed)
3. Ensure both entries are in the same object

## SASS/CSS

- Entry point: `www/sass/main.scss`
- Partials: `_buttons.scss`, `_cards.scss`, `_layout.scss`, `_modals.scss`, `_tables.scss`, `_utils.scss`
- Variables: `www/sass/variables.scss`
- Output: `www/css/main.min.css` (compressed)
- Compilation: `R/shiny-utils/sass.R` (run manually when SASS changes)

## Development Notes

### Disabling Auth0

Set `options(auth0_disable = TRUE)` before running the app. Automatically set in test mode.

### Static asset caching

Browser caching can cause stale JS/CSS files during development. The `ui.R` uses a timestamp
query param for cache-busting:

```r
tags$script(src = sprintf("js/helpers-auth0.js?v=%s", as.integer(Sys.time())))
```

This ensures fresh assets on each app restart. For production, consider using a fixed version
number or file hash instead.
