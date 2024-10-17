FROM golang:1.21 AS polycli-builder
WORKDIR /opt/polygon-cli
RUN git clone https://github.com/maticnetwork/polygon-cli.git . \
  && BUILD_DIR=. make build

FROM nicolaka/netshoot:v0.12
LABEL author="devtools@polygon.technology"
LABEL description="Helper image to debug network issues"
COPY --from=polycli-builder /opt/polygon-cli/polycli /usr/local/bin/polycli
