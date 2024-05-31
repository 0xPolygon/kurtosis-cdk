FROM golang:1.21 AS polycli-builder
ARG POLYCLI_VERSION
WORKDIR /opt/polygon-cli
RUN git clone --branch ${POLYCLI_VERSION} https://github.com/maticnetwork/polygon-cli.git . \
  && CGO_ENABLED=0 go build -o polycli main.go


FROM ubuntu:22.04
LABEL author="devtools@polygon.technology"
LABEL description="Blockchain toolbox"

COPY --from=polycli-builder /opt/polygon-cli/polycli /usr/bin/polycli
COPY --from=polycli-builder /opt/polygon-cli/bindings /opt/bindings
# WARNING (DL3008): Pin versions in apt get install.
# WARNING (DL3013): Pin versions in pip.
# WARNING (DL4006): Set the SHELL option -o pipefail before RUN with a pipe in it
# WARNING (SC1091): (Sourced) file not included in mock.
# hadolint ignore=DL3008,DL3013,DL4006,SC1091
RUN apt-get update \
  && apt-get install --yes --no-install-recommends curl jq git python3-pip \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && pip3 install --no-cache-dir yq \
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --version nightly-f625d0fa7c51e65b4bf1e8f7931cd1c6e2e285e9 \
  && cp /root/.foundry/bin/* /usr/local/bin
