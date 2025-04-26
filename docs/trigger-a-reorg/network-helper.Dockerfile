FROM golang:1.22 AS polycli-builder
WORKDIR /opt/polygon-cli
RUN git clone https://github.com/0xPolygon/polygon-cli.git . \
  && make build

FROM nicolaka/netshoot:v0.12
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to debug network issues"
COPY --from=polycli-builder /opt/polygon-cli/out/polycli /usr/local/bin/polycli
