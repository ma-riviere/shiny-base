# Shiny Base

Base template for Shiny apps with Auth0 authentication and server-side bookmarking.

To authentify in Auth0:
- ma.riviere987@gmail.com
- auth0test&15

When you are unsure about a shiny-related (or adjacent) issue, consult/brainstorm with the Shiny notebookLM (skill). It's a domain expert with access to up-to-date documentation, code examples, books, tutorials, and more.

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

4. **Use reactive params for tight coupling**: When a parent module needs to control exactly
   one child, reactive parameters may still be cleaner than global triggers.

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
- `error_email_enabled`: Whether to send emails on unhandled errors (default: prod only)

### Error notification emails

`R/shiny-utils/error_handling.R` provides automatic error notification:
- `send_error_email(error_msg, session)`: Sends error details with context (user, R version, stack trace)
- `setup_error_handlers(session)`: Registers session-level error handlers (call in `server.R`)
- `setup_global_error_handlers()`: Sets up global error handling (called in `global.R`)

Error emails are only sent in production (`ENV=prod`) when `EMAIL_TO` is configured.

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

## i18n (Internationalization)

Uses `shiny.i18n` for translations. Language resolution hierarchy:
1. Auth0 `user_metadata.language` (source of truth for authenticated users)
2. Cookie (name from `getOption("language_cookie_name")`, 1-year expiry)
3. Browser language preference
4. App default (from `getOption("default_language")`)

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
