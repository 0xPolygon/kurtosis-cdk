# STAGE 1: Clone, build the application
FROM node:20-alpine AS builder
ARG AGGLAYER_DEV_UI_BRANCH="main"
ARG AGGLAYER_DEV_UI_TAG_OR_COMMIT_SHA="844bfbc" # 2026-02-09

# Set environment variables for build (can be overridden at build time)
ARG NEXT_PUBLIC_BRIDGE_HUB_API="http://localhost:8080"
ENV NEXT_PUBLIC_PROJECT_ID="agglayer-dev-ui"
ENV NEXT_PUBLIC_BRIDGE_HUB_API=$NEXT_PUBLIC_BRIDGE_HUB_API

WORKDIR /app

# Install git
RUN apk add --no-cache git

# Clone the repository, install dependencies, and build
RUN git clone --branch ${AGGLAYER_DEV_UI_BRANCH} https://github.com/agglayer/agglayer-dev-ui . \
  && git checkout ${AGGLAYER_DEV_UI_TAG_OR_COMMIT_SHA} \
  && npm ci \
  && npm run build

# STAGE 3: Production image with nginx
FROM nginx:alpine
COPY --from=builder /app/out /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
