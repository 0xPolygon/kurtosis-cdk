FROM golang:1.23 AS polycli-builder
ARG POLYCLI_VERSION
WORKDIR /opt/polygon-cli
RUN git clone --branch ${POLYCLI_VERSION} https://github.com/0xPolygon/polygon-cli.git . \
  && make build


FROM ubuntu:24.04
ARG FOUNDRY_VERSION
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
  && apt-get install --yes --no-install-recommends bc curl git jq pipx \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && pipx ensurepath \
  && pipx install yq \
  && curl --silent --location --proto "=https" https://foundry.paradigm.xyz | bash \
  && /root/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && ln -s /root/.foundry/bin/* /usr/local/bin/ \
  && rm -fr /root/.foundry/versions/*
