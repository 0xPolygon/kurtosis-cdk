FROM rust:slim-bookworm AS builder
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to deploy op-succinct contracts"

# docker build --no-cache --build-arg OP_SUCCINCT_BRANCH=v1.2.11-agglayer --file docker/op-succinct-slim.Dockerfile -t atanmarko/op-succinct-contract-deployer:v1.2.11-agglayer .

# STEP 1: Install Foundry, Rust, and tools.
ARG OP_SUCCINCT_BRANCH
WORKDIR /opt

# WARNING (DL3008): Pin versions in apt get install.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
       curl \
       build-essential \
       ca-certificates \
       git \
       pkg-config \
       libssl-dev \
       clang \
       libclang-dev \
       jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# hadolint ignore=DL4006
RUN curl -sL https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# hadolint ignore=DL4006
RUN curl -sL https://foundry.paradigm.xyz | bash \
    && /root/.foundry/bin/foundryup  --install stable \
    && mv /root/.foundry/bin/* /usr/local/bin/

WORKDIR /opt
RUN git clone https://github.com/succinctlabs/sp1-contracts.git

WORKDIR /opt/op-succinct
RUN git clone https://github.com/agglayer/op-succinct.git . \
    && git checkout ${OP_SUCCINCT_BRANCH} \
    && git submodule update --init --recursive

RUN cargo build --release \
    && cp target/release/fetch-l2oo-config /usr/local/bin/ \
    && cargo clean && rm -rf .git

# INFO (DL3049): Label `author` is missing.
# INFO (DL3049): Label `description` is missing.
# hadolint ignore=DL3049
FROM rust:slim-bookworm
# WARNING (DL3008): Pin versions in apt get install.
# INFO (DL3009): Delete the apt-get lists after installing something
# hadolint ignore=DL3008,DL3009
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        jq git \
    && apt-get clean

COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /opt/op-succinct /opt/op-succinct
COPY --from=builder /opt/sp1-contracts /opt/sp1-contracts
WORKDIR /opt/op-succinct
