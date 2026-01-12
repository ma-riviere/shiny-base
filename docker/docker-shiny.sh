#!/bin/bash

echo "Environment variables at script start:"

# Read AUTH0_CLIENT_SECRET Docker secret file and export as environment variable
if [ -f "/run/secrets/AUTH0_CLIENT_SECRET" ]; then
    export AUTH0_CLIENT_SECRET=$(cat /run/secrets/AUTH0_CLIENT_SECRET)
    echo "Loaded AUTH0_CLIENT_SECRET from Docker secret"
fi

# Add variables to Renviron.site
env_file="/srv/shiny-server/.Renviron"

# Clear existing custom environment variables from the file
sed -i '/^# Custom environment variables/,$d' "${env_file}"

# Add a marker and the current environment variables to the file
echo "# Custom environment variables" >> "${env_file}"
env | while read -r line; do
    var_name="${line%%=*}"
    echo "$line" >> "${env_file}"
done

xtail /var/log/shiny-server/ &
exec env shiny-server 2>&1
