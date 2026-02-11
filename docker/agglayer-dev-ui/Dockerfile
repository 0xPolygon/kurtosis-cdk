FROM nginx:alpine
LABEL author="devtools@polygon.technology"
LABEL description="Agglayer Dev UI"

ARG AGGLAYER_DEV_UI_BRANCH="main"
ARG AGGLAYER_DEV_UI_TAG_OR_COMMIT_SHA="844bfbc" # 2026-02-09

WORKDIR /opt/agglayer-dev-ui
# WARNING (DL3018): Pin versions in apk add.
# hadolint ignore=DL3018
RUN apk add --no-cache git nodejs npm patch \
  && git clone --branch ${AGGLAYER_DEV_UI_BRANCH} https://github.com/agglayer/agglayer-dev-ui . \
  && git checkout ${AGGLAYER_DEV_UI_TAG_OR_COMMIT_SHA} \
  && npm ci

  COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY appMode.ts.diff entrypoint.sh .
RUN patch -p1 -i appMode.ts.diff

ENTRYPOINT ["/bin/sh", "/opt/agglayer-dev-ui/entrypoint.sh"]
