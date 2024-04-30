FROM golang:1.21 AS polycli-builder
ARG POLYCLI_VERSION
WORKDIR /opt/polygon-cli
RUN git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && CGO_ENABLED=0 go build -o polycli main.go


FROM node:20-bookworm
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to deploy zkevm contracts"

# STEP 1: Download zkevm contracts dependencies and compile contracts.
ARG ZKEVM_CONTRACTS_BRANCH
WORKDIR /opt/zkevm-contracts
# FIX: `npm install` randomly fails with ECONNRESET and ETIMEDOUT errors by installing npm>=10.5.1.
# https://github.com/npm/cli/releases/tag/v10.5.1
RUN git clone --branch ${ZKEVM_CONTRACTS_BRANCH} https://github.com/0xPolygonHermez/zkevm-contracts . \
  && npm install --global npm@10.6.0 \
  && npm install \
  && npx hardhat compile

# STEP 2: Install tools.
COPY --from=polycli-builder /opt/polygon-cli/polycli /usr/bin/polycli
WORKDIR /opt
# Note: We download a specific version of foundry because we had issues with the recent releases.
# https://github.com/0xPolygon/kurtosis-cdk/pull/76#issuecomment-2070645918
# WARNING (DL3008): Pin versions in apt get install.
# WARNING (DL3013): Pin versions in pip.
# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# hadolint ignore=DL3008,DL3013,DL4006
RUN apt-get update \
  && apt-get install --yes --no-install-recommends jq python3-pip \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && pip3 install --break-system-packages --no-cache-dir yq \
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --version nightly-f625d0fa7c51e65b4bf1e8f7931cd1c6e2e285e9 \
  && cp /root/.foundry/bin/* /usr/local/bin

USER node
