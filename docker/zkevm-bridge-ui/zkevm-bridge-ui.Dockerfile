FROM node:22-bookworm AS builder

# STEP 1: Clone zkevm-bridge-ui repository and buil the app.
ARG ZKEVM_BRIDGE_UI_TAG
WORKDIR /opt/zkevm-bridge-ui
COPY env.sh env.ts.diff ./
# WARNING (DL3008): Pin versions in apt get install.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install --yes --no-install-recommends git patch \
  && git clone --branch ${ZKEVM_BRIDGE_UI_TAG} https://github.com/0xPolygonHermez/zkevm-bridge-ui . \
  && npm install \
  && npm run build \
  && patch -p1 -i env.ts.diff \
  && ./env.sh \
  && cp .env ./dist


# STEP 2: Serve the app using nginx.
FROM nginx:alpine
LABEL author="devtools@polygon.technology"
LABEL description="Enhanced zkevm-bridge-ui image with relative URLs support enabled"

COPY --from=builder /opt/zkevm-bridge-ui/dist /usr/share/nginx/html
COPY --from=builder /opt/zkevm-bridge-ui/deployment/nginx.conf /etc/nginx/conf.d/default.conf
ENTRYPOINT ["nginx", "-g", "daemon off;"]
