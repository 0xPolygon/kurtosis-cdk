FROM golang:1.22 AS polycli-builder
ARG POLYCLI_VERSION
WORKDIR /opt/polygon-cli
RUN git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && make build


FROM ubuntu:24.04
# Pin foundry version to 2024/10/23 to avoid the issue with cast send.
# https://github.com/foundry-rs/foundry/issues/9276
ARG FOUNDRY_VERSION=nightly-2044faec64f99a21f0e5f0094458a973612d0712
LABEL author="devtools@polygon.technology"
LABEL description="Blockchain toolbox"

COPY --from=polycli-builder /opt/polygon-cli/out/polycli /usr/bin/polycli
COPY --from=polycli-builder /opt/polygon-cli/bindings /opt/bindings
# WARNING (DL3008): Pin versions in apt get install.
# WARNING (DL3013): Pin versions in pip.
# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# WARNING (SC1091): (Sourced) file not included in mock.
# hadolint ignore=DL3008,DL3013,DL4006,SC1091
RUN apt-get update \
  && apt-get install --yes --no-install-recommends curl git jq pipx \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && pipx ensurepath \
  && pipx install yq \
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --version ${FOUNDRY_VERSION} \
  && cp /root/.foundry/bin/* /usr/local/bin
