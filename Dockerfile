# syntax=docker/dockerfile:1
FROM ghcr.io/ma-riviere/docker-shiny:4.6-builder AS builder

# Restore the production lockfile on top of the pre-warmed site library:
# clean = TRUE removes pre-warmed packages not in the lockfile, so the app
# ships exactly its locked set. github_pat enables private GitHub packages.
COPY renv/profiles/docker-4.6/renv.lock /tmp/renv.lock
RUN --mount=type=secret,id=github_pat \
    GITHUB_PAT="$(cat /run/secrets/github_pat 2>/dev/null || true)" \
    Rscript -e '.libPaths(c("/opt/renv-bootstrap", .libPaths())); renv::restore(lockfile = "/tmp/renv.lock", library = Sys.getenv("R_LIBS_SITE"), clean = TRUE, prompt = FALSE)'

RUN find "${R_LIBS_SITE}" -depth -type d \
        \( -name help -o -name html -o -name doc -o -name tests \) -exec rm -rf {} +

FROM ghcr.io/ma-riviere/docker-shiny:4.6-runtime

COPY --from=builder /opt/r-site-library /opt/r-site-library

COPY docker/shiny-server.conf /etc/shiny-server/shiny-server.conf

# App code (changes frequently, last layer). Runs as shiny via the base image
# user/entrypoint; the base entrypoint writes container env to .Renviron.
COPY --chown=shiny:shiny . /srv/shiny-server/

# Use HEAD request to avoid spawning R processes for auth-protected apps
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf --head http://localhost:3838/ || exit 1
