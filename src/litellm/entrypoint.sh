#!/bin/bash
set -e

# Build PostgreSQL connection URL with proper URL encoding for special characters
# This script reads individual database parameters and constructs a valid DATABASE_URL

if [ -n "$DB_HOST" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ] && [ -n "$DB_NAME" ]; then
    # Use Python to properly URL-encode the username and password
    # This ensures special characters like @, :, /, ?, #, etc. don't break the URL parsing
    ENCODED_USER=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${DB_USER}', safe=''))")
    ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${DB_PASSWORD}', safe=''))")

    # Construct the PostgreSQL connection URL
    export DATABASE_URL="postgresql://${ENCODED_USER}:${ENCODED_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

    echo "Database connection configured successfully"
else
    echo "Warning: Database environment variables not fully configured"
    echo "Required: DB_HOST, DB_USER, DB_PASSWORD, DB_NAME"
fi

# Execute the original litellm command with all arguments passed to this script
exec litellm "$@"
