#!/bin/bash
set -euo pipefail

# Generate docker-compose.yml for snapshot
# Usage: generate_compose.sh <output_dir>

OUTPUT_DIR="$1"

cat > "$OUTPUT_DIR/docker-compose.yml" <<'COMPOSE_EOF'
version: '3.8'

services:
  init:
    image: kurtosis-cdk-snapshot-init:latest
    container_name: snapshot-init
    volumes:
      - ./:/snapshot:ro
      - ./runtime:/runtime:rw
      - ./tools/init.sh:/init.sh:ro
    command: /bin/bash /init.sh
    networks:
      - snapshot-net

  geth:
    image: ethereum/client-go:v1.16.8
    container_name: snapshot-geth
    entrypoint: ""
    depends_on:
      init:
        condition: service_completed_successfully
    volumes:
      - ./runtime:/runtime:ro
    command:
      - /bin/sh
      - -c
      - |
        geth init --datadir /tmp/geth-data /runtime/el_genesis.json
        geth --datadir /tmp/geth-data \
          --http --http.addr 0.0.0.0 --http.port 8545 \
          --http.api eth,net,web3,debug,txpool \
          --http.corsdomain '*' --http.vhosts '*' \
          --ws --ws.addr 0.0.0.0 --ws.port 8546 \
          --ws.api eth,net,web3,debug,txpool --ws.origins '*' \
          --authrpc.addr 0.0.0.0 --authrpc.port 8551 \
          --authrpc.vhosts '*' --authrpc.jwtsecret /runtime/jwt.hex \
          --syncmode full --gcmode archive --networkid 1337 \
          --nodiscover --maxpeers 0 --mine \
          --miner.etherbase 0x8943545177806ED17B9F23F0a21ee5948eCaa776 \
          --allow-insecure-unlock
    ports:
      - "8545:8545"
      - "8546:8546"
      - "8551:8551"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:8545"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 30s
    networks:
      - snapshot-net

  lighthouse-bn:
    image: sigp/lighthouse:v8.1.0
    container_name: snapshot-lighthouse-bn
    depends_on:
      geth:
        condition: service_healthy
    volumes:
      - ./runtime:/runtime:ro
    command: >
      lighthouse bn
        --datadir /tmp/lighthouse-bn
        --testnet-dir /runtime/cl
        --execution-endpoint http://geth:8551
        --execution-jwt /runtime/jwt.hex
        --http
        --http-address 0.0.0.0
        --http-port 5052
        --disable-enr-auto-update
        --enr-address 127.0.0.1
        --enr-udp-port 9000
        --enr-tcp-port 9000
        --port 9000
        --target-peers 0
        --boot-nodes ""
        --allow-insecure-genesis-sync
    ports:
      - "5052:5052"
      - "9000:9000"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:5052/eth/v1/node/version"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 20s
    networks:
      - snapshot-net

  lighthouse-vc:
    image: sigp/lighthouse:v8.1.0
    container_name: snapshot-lighthouse-vc
    depends_on:
      lighthouse-bn:
        condition: service_started
    volumes:
      - ./runtime:/runtime:rw
    command: >
      lighthouse vc
        --testnet-dir /runtime/cl
        --beacon-nodes http://lighthouse-bn:5052
        --init-slashing-protection
        --validators-dir /runtime/val/validators
        --secrets-dir /runtime/val/secrets
        --suggested-fee-recipient 0x8943545177806ED17B9F23F0a21ee5948eCaa776
    networks:
      - snapshot-net

networks:
  snapshot-net:
    driver: bridge
COMPOSE_EOF

echo "Docker compose file created: $OUTPUT_DIR/docker-compose.yml"
