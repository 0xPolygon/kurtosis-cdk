FROM golang:1.22 AS polycli-builder
ARG POLYCLI_VERSION
WORKDIR /opt/polygon-cli
RUN git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && make build


FROM node:22-bookworm
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to deploy zkevm contracts"

# STEP 1: Download zkevm contracts dependencies and compile contracts.
ARG ZKEVM_CONTRACTS_BRANCH
WORKDIR /opt/zkevm-contracts
RUN git clone https://github.com/0xPolygonHermez/zkevm-contracts . \
  && git checkout ${ZKEVM_CONTRACTS_BRANCH} \
  && npm install --global npm@10.9.0 \
  && npm install \
  && npx hardhat compile

# STEP 2: Install tools.
ARG FOUNDRY_VERSION
COPY --from=polycli-builder /opt/polygon-cli/out/polycli /usr/bin/polycli
WORKDIR /opt
# WARNING (DL3008): Pin versions in apt get install.
# WARNING (DL3013): Pin versions in pip.
# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# hadolint ignore=DL3008,DL3013,DL4006
RUN apt-get update \
  && apt-get install --yes --no-install-recommends curl git jq pipx \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && pipx ensurepath \
  && pipx install yq \
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && cp /root/.foundry/bin/* /usr/local/bin

USER node
