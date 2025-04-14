FROM debian:bookworm-slim AS builder
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to deploy op-succinct contracts"

# docker build --build-arg OP_SUCCINCT_BRANCH=v1.2.7-agglayer --build-arg RUST_VERSION=1.84.1 --build-arg FOUNDRY_VERSION=stable  --file op-succinct-slim.Dockerfile -t nulyjkdhthz/op-succinct-contract-deployer:v1.2.7-agglayer .
# docker build --build-arg OP_SUCCINCT_BRANCH=v1.2.5-agglayer --build-arg RUST_VERSION=1.84.1 --build-arg FOUNDRY_VERSION=stable  --file op-succinct-slim.Dockerfile -t nulyjkdhthz/op-succinct-contract-deployer:v1.2.5-agglayer .

# STEP 1: Install Foundry, Rust, and tools.
ARG RUST_VERSION
ARG FOUNDRY_VERSION
ARG OP_SUCCINCT_BRANCH
WORKDIR /opt
ENV PATH="/home/nonroot/.cargo/bin:${PATH}"

# Create a non-root user
RUN useradd -ms /bin/bash nonroot

# WARNING (DL3008): Pin versions in apt get install.
# WARNING (DL3013): Pin versions in pip.
# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# hadolint ignore=DL3008,DL3013,DL4006
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        curl \
        build-essential \
        ca-certificates \
        bash \
        git \
        pkg-config \
        libssl-dev \
        clang \
        libclang-dev \
        cargo \
        jq \
        pipx \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | su - nonroot -c "sh -s -- --default-toolchain ${RUST_VERSION} -y" \
    && su - nonroot -c "/home/nonroot/.cargo/bin/rustup toolchain install ${RUST_VERSION}" \
    && curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | su - nonroot -c "bash -s -- --to /home/nonroot/just" \
    && cp /home/nonroot/just/* /usr/local/bin \
    && pipx ensurepath \
    && pipx install yq \
    && curl --proto "=https" --tlsv1.2 -sSf -L https://foundry.paradigm.xyz | su - nonroot -c "bash" \
    && su - nonroot -c "/home/nonroot/.foundry/bin/foundryup --install ${FOUNDRY_VERSION}" \
    && cp /home/nonroot/.foundry/bin/* /usr/local/bin

RUN cd /opt \
    && git clone https://github.com/succinctlabs/sp1-contracts.git

WORKDIR /opt/op-succinct

RUN git clone https://github.com/agglayer/op-succinct.git . \
    && git checkout ${OP_SUCCINCT_BRANCH} \
    && git submodule update --init --recursive

RUN cargo build --release
RUN find target/release -maxdepth 1 -type f -executable | xargs -I xxx cp xxx /usr/local/bin/
RUN cargo clean

FROM debian:bookworm-slim
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
