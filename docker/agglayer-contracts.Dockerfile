FROM golang:1.23 AS polycli-builder
ARG POLYCLI_BRANCH="main"
ARG POLYCLI_TAG_OR_COMMIT_SHA="v0.1.83" # 2025-07-02
WORKDIR /opt/polygon-cli
RUN git clone --branch ${POLYCLI_BRANCH} https://github.com/0xPolygon/polygon-cli.git . \
  && git checkout ${POLYCLI_TAG_OR_COMMIT_SHA} \
  && make build


FROM node:22-bookworm
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to deploy agglayer contracts"

ARG AGGLAYER_CONTRACTS_BRANCH="main"
ARG AGGLAYER_CONTRACTS_TAG_OR_COMMIT_SHA="4af560f4d899fdd26f7714f15560e8316034c2f1" # 2025-07-01
ARG FOUNDRY_VERSION="v1.2.3"

# STEP 1: Download agglayer contracts dependencies and compile contracts.
WORKDIR /opt/zkevm-contracts
RUN git clone --branch ${AGGLAYER_CONTRACTS_BRANCH} https://github.com/agglayer/agglayer-contracts . \
  && git checkout ${AGGLAYER_CONTRACTS_TAG_OR_COMMIT_SHA} \
  && npm install --global npm@10.9.0 \
  && npm install \
  && npx hardhat compile

# STEP 2: Install tools.
COPY --from=polycli-builder /opt/polygon-cli/out/polycli /usr/bin/polycli
WORKDIR /opt
# WARNING (DL3008): Pin versions in apt get install.
# WARNING (DL3013): Pin versions in pip.
# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# hadolint ignore=DL3008,DL3013,DL4006
RUN apt-get update \
  && apt-get install --yes --no-install-recommends curl git jq pipx python3-pip \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && pipx ensurepath \
  && pipx install yq \
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && cp /root/.foundry/bin/* /usr/local/bin \
  && pip3 install --no-cache-dir --break-system-packages flask flask_wtf gunicorn

USER node
