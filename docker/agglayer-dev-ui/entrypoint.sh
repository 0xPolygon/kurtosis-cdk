#!/bin/sh

# Docker entrypoint script for agglayer-dev-ui.
# Builds the app at runtime (not during docker build) to allow custom chain
# configurations via modified source files.
AGGLAYER_DEV_UI_FOLDER_PATH="/opt/agglayer-dev-ui"

# Create .env
ENV_FILE_PATH="$AGGLAYER_DEV_UI_FOLDER_PATH/.env.local"
echo "NEXT_PUBLIC_PROJECT_ID=agglayer-dev-ui" > $ENV_FILE_PATH
echo "NEXT_PUBLIC_BRIDGE_HUB_API=$BRIDGE_HUB_API_URL" >> $ENV_FILE_PATH

# Copy the custom chain configuration.
rm $AGGLAYER_DEV_UI_FOLDER_PATH/app/config.ts
mv /etc/agglayer-dev-ui/config.ts $AGGLAYER_DEV_UI_FOLDER_PATH/app/config.ts

# Build the application from source.
# The source code is mounted/copied into /app during the docker build.
cd $AGGLAYER_DEV_UI_FOLDER_PATH
npm run build

# Copy the build artifacts to nginx's web root.
# This makes the built static files available for nginx to serve.
cp -r $AGGLAYER_DEV_UI_FOLDER_PATH/out/. /usr/share/nginx/html

# Start nginx in the foreground.
# The 'daemon off' directive keeps nginx running as the main process,
# preventing the container from exiting.
nginx -g 'daemon off;'
