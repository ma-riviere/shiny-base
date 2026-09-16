# syntax=docker/dockerfile:1
# One Dockerfile, two stages. Each FROM starts from a separate docker-shiny base image.
# Only the last stage becomes the deployed app image.

# 1. Builder: R + compilation tools + preinstalled R packages.
FROM ghcr.io/ma-riviere/docker-shiny:4.6-builder AS builder

# Make the package library match the app's production lockfile: reuse matching packages,
# install missing/different versions, remove unlisted packages (clean = TRUE).
# Copy only the lockfile here: code-only changes can reuse the cached package installation.
# The GitHub PAT is mounted as a build secret to install private packages.
COPY renv/profiles/docker-4.6/renv.lock /tmp/renv.lock
RUN --mount=type=secret,id=github_pat \
    GITHUB_PAT="$(cat /run/secrets/github_pat 2>/dev/null || true)" \
    Rscript -e '.libPaths(c("/opt/renv-bootstrap", .libPaths())); renv::restore(lockfile = "/tmp/renv.lock", library = Sys.getenv("R_LIBS_SITE"), clean = TRUE, prompt = FALSE)'

# Drop package documentation and tests to reduce the library's size.
RUN find "${R_LIBS_SITE}" -depth -type d \
        \( -name help -o -name html -o -name doc -o -name tests \) -exec rm -rf {} +

# 2. Runtime: start fresh from R + Shiny Server, using the same R minor version as the builder.
# This stage does not inherit the builder's files or compilation tools.
FROM ghcr.io/ma-riviere/docker-shiny:4.6-runtime

# Copy the finished R package library from stage 1. No package installation at startup.
COPY --from=builder /opt/r-site-library /opt/r-site-library

COPY docker/shiny-server.conf /etc/shiny-server/shiny-server.conf

# Code goes last because it changes most often. Earlier layers stay cached when only code changes.
# The base image runs as user shiny; copied app files belong to that user too.
COPY --chown=shiny:shiny . /srv/shiny-server/

# Check that Shiny Server responds without starting R. This does not check that the R app works.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf --head http://localhost:3838/ || exit 1

# At container startup: check writable folders and DB access, apply the schema, verify expected columns.
# If any check fails, && prevents Shiny Server from starting and the container exits.
# The base image's startup script writes the container env to .Renviron (Shiny Server scrubs R's env),
# then starts Shiny Server and forwards its logs to stdout.
CMD ["bash", "-c", "Rscript /srv/shiny-server/docker/prestart.R && exec /usr/local/bin/docker-shiny.sh"]
