FROM alpine:3.20 AS builder
ARG ZKEVM_BRIDGE_UI_BRANCH="develop"
ARG ZKEVM_BRIDGE_UI_TAG_OR_COMMIT_SHA="0006445" # 2024-03-13

WORKDIR /opt/zkevm-bridge-ui
# WARNING (DL3018): Pin versions in apk add.
# hadolint ignore=DL3018
RUN apk add --no-cache git patch \
  && rm -rf /var/cache/apk/* \
  && git clone --branch ${ZKEVM_BRIDGE_UI_BRANCH} https://github.com/0xPolygonHermez/zkevm-bridge-ui . \
  && git checkout ${ZKEVM_BRIDGE_UI_TAG_OR_COMMIT_SHA}

COPY deploy.sh.diff env.ts.diff ./
RUN patch -p1 -i deploy.sh.diff \
  && patch -p1 -i env.ts.diff


FROM nginx:alpine
LABEL author="devtools@polygon.technology"
LABEL description="Enhanced zkevm-bridge-ui image with relative URLs support enabled"

WORKDIR /app
COPY --from=builder /opt/zkevm-bridge-ui/package.json /opt/zkevm-bridge-ui/package-lock.json ./
COPY --from=builder /opt/zkevm-bridge-ui/scripts ./scripts
COPY --from=builder /opt/zkevm-bridge-ui/abis ./abis
COPY --from=builder /opt/zkevm-bridge-ui/ .

# WARNING (DL3018): Pin versions in apk add.
# hadolint ignore=DL3018
RUN apk add --no-cache nodejs npm \
  && rm -rf /var/cache/apk/* \
  && npm install

WORKDIR /
ENTRYPOINT ["/bin/sh", "/app/scripts/deploy.sh"]
