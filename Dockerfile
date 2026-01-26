# syntax=docker/dockerfile:1
FROM ghcr.io/ma-riviere/docker-shiny:4.5

USER root
WORKDIR /srv/shiny-server

# Copy and restore renv with production profile (cached unless renv files change)
# GITHUB_PAT secret enables installing packages from private GitHub repos
COPY --chown=shiny:shiny renv/ ./renv/
ENV RENV_PROFILE=docker-4.5
RUN --mount=type=secret,id=GITHUB_PAT,env=GITHUB_PAT \
    R -e "source('renv/activate.R'); renv::restore()"

# Copy custom Shiny Server configuration
COPY --chown=shiny:shiny docker/shiny-server.conf /etc/shiny-server/shiny-server.conf

# Copy app code (changes frequently)
COPY --chown=shiny:shiny . /srv/shiny-server/
RUN chmod +x /srv/shiny-server/docker/docker-shiny.sh

USER shiny

# Use HEAD request to avoid spawning R processes for auth-protected apps
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf --head http://localhost:3838/ || exit 1

ENTRYPOINT ["/srv/shiny-server/docker/docker-shiny.sh"]
