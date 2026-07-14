# Shiny Base

A sandbox app for trying out production-Shiny patterns end to end: Auth0 login that survives server-side bookmarking, async model fitting, role-based access control, and a Dockerized CI deploy. The app itself is deliberately small (upload a dataset, explore it, fit a linear model on it); the plumbing around it is the point. This is a personal demo, not a template, and none of it is meant to be reused as-is.

## What's inside

- Auth0 authentication (OAuth2 + PKCE) via a custom `auth0r` package, integrated with Shiny's server-side bookmarking
- Non-blocking model fitting with `ExtendedTask` + `mirai`
- Role-based permissions (`data/permissions.yaml`), admin panel, i18n, session tracking, OpenTelemetry traces
- PostgreSQL in production, SQLite in dev and tests; users/datasets/models live in a schema shared with `plumber2-base`, the same app rebuilt on plumber2
- bslib (Bootstrap 5) UI, tested with shinytest2 and Playwright
- Two-stage Docker build, deployed from GitHub Actions to a Docker Compose host with health-gated rollouts

## Running it

Needs an Auth0 tenant (or `options(auth0_disable = TRUE)`) and the environment variables listed in `.Renviron.example`:

```r
renv::restore()
shiny::runApp(port = 9090)
```
