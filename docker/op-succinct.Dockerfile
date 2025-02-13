FROM ubuntu:22.04
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to deploy op-succinct contracts"

# STEP 1: Install Rust and tools.
ARG RUST_VERSION
WORKDIR /opt
RUN apt-get update \
    && apt-get install -y \
        curl \
        build-essential \
        ca-certificates \
        bash \
        git \
        pkg-config \
        libssl-dev \
        clang \
        libclang-dev \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain ${RUST_VERSION} -y \
    && /root/.cargo/bin/rustup toolchain install ${RUST_VERSION} \
    && . $HOME/.cargo/env \
    && curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /root/just \
    && cp /root/just/* /usr/local/bin


# STEP 2: Download op-succinct contract dependencies.
ARG OP_SUCCINCT_BRANCH
WORKDIR /opt/op-succinct
RUN git clone https://github.com/succinctlabs/op-succinct.git . \
  && git checkout ${OP_SUCCINCT_BRANCH} \
  && git submodule update --init --recursive

# STEP 3: Install tools.
ARG FOUNDRY_VERSION
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