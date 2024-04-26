FROM golang:1.21 AS polycli-builder
ARG POLYCLI_VERSION
WORKDIR /opt/polygon-cli
RUN git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && CGO_ENABLED=0 go build -o polycli main.go


FROM node:20-bookworm
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to build zkevm contracts"

# STEP 1: Download zkevm contracts dependencies and compile contracts.
ARG ZKEVM_CONTRACTS_BRANCH
WORKDIR /opt/zkevm-contracts
RUN git clone --branch ${ZKEVM_CONTRACTS_BRANCH} https://github.com/0xPolygonHermez/zkevm-contracts . \
  && npm install --ignore-scripts \
  && npx hardhat compile

# STEP 2: Install tools.
COPY --from=polycli-builder /opt/polygon-cli/polycli /usr/bin/polycli
WORKDIR /opt
# Note: We download a specific version of foundry because we had issues with the recent releases.
# https://github.com/0xPolygon/kurtosis-cdk/pull/76#issuecomment-2070645918
# WARNING (DL3008): Pin versions in apt get install.
# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# WARNING (SC1091): (Sourced) file not included in mock.
# hadolint ignore=DL3008,DL4006,SC1091
RUN apt-get update \
  && apt-get install --yes --no-install-recommends jq python3-pip \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && pip3 install --break-system-packages yq \
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --version nightly-f625d0fa7c51e65b4bf1e8f7931cd1c6e2e285e9 \
  && cp /root/.foundry/bin/* /usr/local/bin

USER node
