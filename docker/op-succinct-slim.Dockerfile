FROM rust:slim-bookworm AS builder
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to deploy op-succinct contracts"

# docker build --no-cache --build-arg OP_SUCCINCT_BRANCH=v1.2.11-agglayer --file docker/op-succinct-slim.Dockerfile -t atanmarko/op-succinct-contract-deployer:v1.2.11-agglayer .

# STEP 1: Install Foundry, Rust, and tools.
ARG OP_SUCCINCT_BRANCH
WORKDIR /opt

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

RUN curl -sL https://just.systems/install.sh | bash -s -- --to /usr/local/bin

RUN curl -sL https://foundry.paradigm.xyz | bash \
    && /root/.foundry/bin/foundryup  --install stable \
    && mv /root/.foundry/bin/* /usr/local/bin/

RUN cd /opt \
    && git clone https://github.com/succinctlabs/sp1-contracts.git

WORKDIR /opt/op-succinct

RUN git clone https://github.com/agglayer/op-succinct.git . \
    && git checkout ${OP_SUCCINCT_BRANCH} \
    && git submodule update --init --recursive

RUN cargo build --release
# RUN find target/release -maxdepth 1 -type f -executable | xargs -I xxx cp xxx /usr/local/bin/
RUN cp target/release/fetch-rollup-config /usr/local/bin/
RUN cargo clean && rm -rf .git

FROM rust:slim-bookworm
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
