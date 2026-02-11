#!/bin/sh

# Docker entrypoint script for agglayer-dev-ui.
# Builds the app at runtime (not during docker build) to allow custom chain
# configurations via modified source files.

# Build the application from source.
# The source code is mounted/copied into /app during the docker build.
cd /app
npm run build

# Copy the build artifacts to nginx's web root.
# This makes the built static files available for nginx to serve.
cp -r /app/dist/. /usr/share/nginx/html

# After building, we only need the compiled artifacts, not the source.
rm -rf /app

# Start nginx in the foreground.
# The 'daemon off' directive keeps nginx running as the main process,
# preventing the container from exiting.
nginx -g 'daemon off;'
