FROM alpine:3.19 AS builder

# STEP 1: Clone zkevm-bridge-ui repository.
ARG ZKEVM_BRIDGE_UI_TAG
WORKDIR /opt/zkevm-bridge-ui
# WARNING (DL3018): Pin versions in apk add.
# hadolint ignore=DL3018
RUN apk add --no-cache git patch \
  && rm -rf /var/cache/apk/* \
  && git clone --branch ${ZKEVM_BRIDGE_UI_TAG} https://github.com/0xPolygonHermez/zkevm-bridge-ui .

# STEP 2: Apply patches.
COPY deploy.sh.diff env.ts.diff ./
RUN patch -p1 -i deploy.sh.diff \
  && patch -p1 -i env.ts.diff


# STEP 3: Build zkevm-bridge-ui image using the official Dockerfile.
FROM nginx:alpine
LABEL author="devtools@polygon.technology"
LABEL description="Enhanced zkevm-bridge-ui image with relative URLs support enabled"

# WARNING (DL3018): Pin versions in apk add.
# hadolint ignore=DL3018
RUN apk add --no-cache nodejs npm \
  && rm -rf /var/cache/apk/*

WORKDIR /app
COPY --from=builder /opt/zkevm-bridge-ui/package.json /opt/zkevm-bridge-ui/package-lock.json ./
COPY --from=builder /opt/zkevm-bridge-ui/scripts ./scripts
COPY --from=builder /opt/zkevm-bridge-ui/abis ./abis
RUN npm install
COPY --from=builder /opt/zkevm-bridge-ui/ .

WORKDIR /
ENTRYPOINT ["/bin/sh", "/app/scripts/deploy.sh"]
