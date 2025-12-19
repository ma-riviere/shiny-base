# Shiny Base

Base template for Shiny apps with Auth0 authentication and server-side bookmarking.

To authentify in Auth0:
- ma.riviere987@gmail.com
- auth0test&15

## Navigation

The app uses `bslib::page_navbar()` for navigation with a shared sidebar across all pages.
- Navigation tabs are defined as `bslib::nav_panel()` elements
- The active tab is tracked via `input$nav` (automatically bookmarked by Shiny)
- Use `bslib::nav_select("nav", "page_value", session = session)` to programmatically switch tabs

## Auth0 + Bookmarking Integration

The standard `auth0` package is incompatible with Shiny's server-side bookmarking because:
1. Auth0 rejects redirect URIs containing query params (like `?_state_id_=xxx`)
2. The `auth0:::has_auth_code()` function requires exact state match

`R/helpers_auth0.R` provides custom wrappers (`auth0_ui2`, `auth0_server2`) that solve this.

### How it works

1. **Outbound**: User visits `/?_state_id_=xyz`. `auth0_ui2` encodes the bookmark ID in Auth0's
   state param as `originalState|bookmarkId`, keeping the redirect_uri clean, then redirects
   to Auth0.

2. **Auth0 Callback**: Auth0 redirects back with `?code=...&state=originalState|bookmarkId`.
   `auth0_ui2` detects valid auth code and extracts the bookmark ID from the state param.

3. **Bookmark Redirect**: If a bookmark ID was encoded in the state but `_state_id_` is not in
   the URL, `auth0_ui2` redirects to add `_state_id_` to the URL (keeping code/state params).
   This triggers Shiny's native bookmark restoration mechanism.

4. **Native Restoration**: Shiny sees `_state_id_` in the URL and automatically restores all
   inputs from `shiny_bookmarks/{id}/input.rds`. This includes the active tab (`input$nav`)
   which `bslib::page_navbar()` handles automatically.

5. **Token Exchange**: `auth0_server2` exchanges the auth code for tokens and populates
   `session$userData$auth0_info`.

6. **URL Cleanup**: `www/js/auth0-helpers.js` removes `code`, `state`, and `_state_id_` from
   the URL after Shiny connects.

### Key components

- `auth0_ui2`: Encodes `_state_id_` in Auth0's state param, redirects to add `_state_id_` after callback
- `auth0_server2`: Handles token exchange and logout
- `www/js/auth0-helpers.js`: Cleans up URL params after Auth0 callback

### Excluded inputs

Some inputs must be excluded from bookmarking via `setBookmarkExclude()` in `server.R`:
- `sidebar-toggle`: Action buttons with `shinyActionButtonValue` class cause restoration errors

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

## Development Notes

### Static asset caching

Browser caching can cause stale JS/CSS files during development. The `ui.R` uses a timestamp
query param for cache-busting:

```r
tags$script(src = sprintf("js/auth0-helpers.js?v=%s", as.integer(Sys.time())))
```

This ensures fresh assets on each app restart. For production, consider using a fixed version
number or file hash instead.
