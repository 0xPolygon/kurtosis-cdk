FROM alpine:3.20 AS builder

# STEP 1: Clone zkevm-bridge-ui repository.
ARG ZKEVM_BRIDGE_UI_TAG
WORKDIR /opt/zkevm-bridge-ui
# WARNING (DL3018): Pin versions in apk add.
# hadolint ignore=DL3018
RUN apk add --no-cache git nodejs npm patch \
  && rm -rf /var/cache/apk/* \
  && git clone --branch ${ZKEVM_BRIDGE_UI_TAG} https://github.com/0xPolygonHermez/zkevm-bridge-ui .

# STEP 2: Apply patches and build the app.
COPY deploy.sh.diff env.ts.diff ./
RUN patch -p1 -i deploy.sh.diff \
  && patch -p1 -i env.ts.diff \
  && npm install \
  && npm run build


# STEP 3: Serve the app using nginx.
FROM nginx:alpine
LABEL author="devtools@polygon.technology"
LABEL description="Enhanced zkevm-bridge-ui image with relative URLs support enabled"

COPY --from=builder /opt/zkevm-bridge-ui/dist /usr/share/nginx/html
COPY --from=builder /opt/zkevm-bridge-ui/deployment/nginx.conf /etc/nginx/conf.d/default.conf

WORKDIR /app
COPY --from=builder /opt/zkevm-bridge-ui/scripts ./scripts
ENTRYPOINT ["/bin/sh", "/app/scripts/deploy.sh"]
