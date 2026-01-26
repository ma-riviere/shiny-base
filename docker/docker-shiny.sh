#!/bin/bash

# Shiny Server sanitizes environment variables when spawning R processes.
# Docker env_file values won't reach R unless we write them to .Renviron.
# This script dumps app-specific env vars, excluding system/Docker internals.

env_file="/srv/shiny-server/.Renviron"

# System/Docker vars to exclude (regex pattern)
exclude_pattern="^(PATH|HOME|HOSTNAME|USER|SHELL|PWD|OLDPWD|TERM|SHLVL|_|DOCKER_|KUBERNETES_|container)="

# Write app env vars to .Renviron (overwrite to avoid stale values)
env | grep -vE "$exclude_pattern" > "$env_file"

# Secure permissions (readable only by owner)
chmod 600 "$env_file"

# Start log tailing and shiny-server
xtail /var/log/shiny-server/ &
exec shiny-server 2>&1
