FROM node:22-bookworm AS builder

# STEP 1: Clone zkevm-bridge-ui repository.
ARG ZKEVM_BRIDGE_UI_TAG
WORKDIR /opt/zkevm-bridge-ui
# WARNING (DL3008): Pin versions in apt get install.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install --yes --no-install-recommends git patch \
  && git clone --branch ${ZKEVM_BRIDGE_UI_TAG} https://github.com/0xPolygonHermez/zkevm-bridge-ui .

# STEP 2: Apply patches and build the app.
COPY env.ts.diff .
RUN patch -p1 -i env.ts.diff \
  && npm install \
  && npm run build


# STEP 3: Serve the app using nginx.
FROM nginx:alpine
LABEL author="devtools@polygon.technology"
LABEL description="Enhanced zkevm-bridge-ui image with relative URLs support enabled"

COPY --from=builder /opt/zkevm-bridge-ui/dist /usr/share/nginx/html
COPY --from=builder /opt/zkevm-bridge-ui/deployment/nginx.conf /etc/nginx/conf.d/default.conf
ENTRYPOINT ["nginx", "-g", "daemon off;"]
