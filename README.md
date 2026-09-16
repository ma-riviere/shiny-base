# Shiny Base

A personal sandbox for trying out production Shiny patterns: authentication, bookmarking, async work, permissions and deployment. The app itself is deliberately small: upload a CSV, browse it, fit a linear model. The plumbing around it is the point.

## What's inside

- CSV upload, table preview, dataset renaming/download/deletion (subject to permissions)
- Non-blocking linear model fitting with `ExtendedTask` + `mirai`; successful fits are saved automatically and can be loaded or deleted
- Optional dataset assistant (`shinychat` + `ellmer`): a local llama.cpp model answers questions through sandboxed DuckDB queries over the selected dataset
- Auth0 login (OAuth2 + PKCE), email verification, server-side bookmarks saved on disconnect and restored after login
- Role-based permissions, admin panel with user bans, session tracking, logs and OpenTelemetry traces
- bslib (Bootstrap 5) UI, English/French translations
- PostgreSQL in production, SQLite in dev and tests

The app is split into numbered UI/server modules in `R/`. Shared utilities live in `shinyutils`, authentication in `auth0r`. Both are private packages. Users, datasets and models share a Postgres schema with `plumber2-base`, the same app rebuilt on plumber2.

## Running it

This repo depends on my private packages and infrastructure, so running it requires access to those dependencies. Use R 4.6 (the dev lockfile records 4.6.1) and a `GITHUB_PAT` with access to `ma-riviere/auth0r` and `ma-riviere/shinyutils`.

From the project root:

```sh
git submodule update --init --recursive
cp .Renviron.example .Renviron
```

In `.Renviron`, replace `ENV=dev/prod` with `ENV=dev`. For local use without Auth0, set `AUTH0_DISABLE=true` and `DEV_ROLES=admin`. SQLite is used locally; no Postgres server is needed.

Start a fresh R session in the project directory. `.Rprofile` selects the `dev-4.6` renv profile:

```r
renv::restore()
shiny::runApp(port = 9090)
```

For real login, leave `AUTH0_DISABLE` unset and configure the Auth0 values in `.Renviron`. Register `AUTH0_APP_URL` as the callback/logout URL in your tenant. Restart R after changing `.Renviron`.

**Dataset assistant:** off by default. Set `CHAT_ENABLED=true`, `CHAT_BASE_URL` to a reachable OpenAI-compatible endpoint, `CHAT_MODEL`, and optionally `CHAT_API_KEY`. The default endpoint (`http://llm:8080/v1`) belongs to the deployment's Docker network. Conversations are not saved; switching datasets or pressing "New chat" clears them.

## Tests and deployment

Shiny tests: `shinytest2::test_app()` from the project root, with Chrome/Chromium installed and port 9090 free. These tests start their own app.

Browser tests: run `npm ci --prefix tests/e2e` and `npm run test:setup`, start the app on port 9090, then `npm run test:workflow`. CI runs shinytest2 and Playwright with Auth0 disabled; real login tests need the test accounts listed in `.Renviron.example`.

GitHub Actions builds a two-stage Docker image and deploys it through Docker Compose, waiting for the container healthcheck. The Compose file starts only the app: Traefik, Postgres, the model service and their networks are provisioned separately.

See [NOTES.md](NOTES.md) for the implementation choices and maintenance details.
