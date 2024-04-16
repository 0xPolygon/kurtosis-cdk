FROM golang:1.21 AS polycli-builder
WORKDIR /opt/polygon-cli
RUN git clone https://github.com/maticnetwork/polygon-cli.git . \
  && CGO_ENABLED=0 go build -o polycli main.go

FROM nicolaka/netshoot:latest
COPY --from=polycli-builder /opt/polygon-cli/polycli /usr/local/bin/polycli
