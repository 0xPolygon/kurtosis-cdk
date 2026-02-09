#!/bin/bash
set -euo pipefail

# Generate docker-compose.yml for snapshot
# Usage: generate_compose.sh <output_dir>

OUTPUT_DIR="$1"

# Check if OP stack config exists
HAS_OP_STACK=false
L2_CHAIN_ID=""
if [ -d "$OUTPUT_DIR/op" ]; then
    ROLLUP_FILE=$(find "$OUTPUT_DIR/op" -name "rollup-*.json.template" -o -name "rollup-*.json" 2>/dev/null | head -1)
    if [ -n "$ROLLUP_FILE" ]; then
        HAS_OP_STACK=true
        # Find L2 chain ID from rollup config filename
        L2_CHAIN_ID=$(basename "$ROLLUP_FILE" | sed 's/rollup-\([0-9]*\)\.json.*/\1/')
        echo "Detected OP stack configuration (L2 Chain ID: $L2_CHAIN_ID)"
    fi
fi

# Start generating docker-compose.yml
cat > "$OUTPUT_DIR/docker-compose.yml" <<'COMPOSE_HEADER'
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
COMPOSE_HEADER

# Add OP stack services if configuration exists
if [ "$HAS_OP_STACK" = true ]; then
    cat >> "$OUTPUT_DIR/docker-compose.yml" <<COMPOSE_OP_STACK

  op-geth:
    image: us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101608.0
    container_name: snapshot-op-geth
    entrypoint: ""
    depends_on:
      lighthouse-bn:
        condition: service_started
    volumes:
      - ./op:/op-config:ro
      - ./runtime:/runtime:ro
    command:
      - /bin/sh
      - -c
      - |
        # Use patched genesis from runtime if available, otherwise use original
        if [ -f /runtime/op/genesis-${L2_CHAIN_ID}.json ]; then
          GENESIS_FILE=/runtime/op/genesis-${L2_CHAIN_ID}.json
        else
          GENESIS_FILE=/op-config/genesis-${L2_CHAIN_ID}.json
        fi
        geth init --datadir=/tmp/op-geth-data --state.scheme=hash \$\$GENESIS_FILE
        geth --networkid=${L2_CHAIN_ID} \\
          --verbosity=3 \\
          --datadir=/tmp/op-geth-data \\
          --gcmode=archive \\
          --state.scheme=hash \\
          --http --http.addr=0.0.0.0 --http.port=8545 \\
          --http.vhosts='*' --http.corsdomain='*' \\
          --http.api=admin,engine,net,eth,web3,debug,miner \\
          --ws --ws.addr=0.0.0.0 --ws.port=8546 \\
          --ws.api=admin,engine,net,eth,web3,debug,miner \\
          --ws.origins='*' \\
          --allow-insecure-unlock \\
          --authrpc.port=8551 \\
          --authrpc.addr=0.0.0.0 \\
          --authrpc.vhosts='*' \\
          --authrpc.jwtsecret=/runtime/jwt.hex \\
          --syncmode=full \\
          --nodiscover --maxpeers=0 \\
          --rpc.allow-unprotected-txs
    ports:
      - "9545:8545"
      - "9546:8546"
      - "9551:8551"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:8545"]
      interval: 5s
      timeout: 3s
      retries: 15
      start_period: 30s
    networks:
      - snapshot-net

  op-node:
    image: us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.16.6
    container_name: snapshot-op-node
    entrypoint: /bin/sh
    depends_on:
      op-geth:
        condition: service_healthy
      lighthouse-bn:
        condition: service_started
      geth:
        condition: service_healthy
    volumes:
      - ./op:/op-config:rw
      - ./runtime:/runtime:ro
    command:
      - -c
      - |
        # Patch rollup config with fresh L1 genesis
        echo "Patching rollup config with L1 genesis..."
        ROLLUP_TEMPLATE=\$\$(ls /op-config/rollup-*.json.template 2>/dev/null | head -1)
        if [ -n "\$\$ROLLUP_TEMPLATE" ]; then
          ROLLUP_OUT=\$\$(basename "\$\$ROLLUP_TEMPLATE" .template)

          # Wait for L1 to be ready and get genesis hash
          for i in {1..60}; do
            L1_HASH=\$\$(wget -q -O- http://geth:8545 --header='Content-Type: application/json' --post-data='{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' 2>/dev/null | grep -o '"hash":"0x[^"]*"' | cut -d'"' -f4 || true)
            if [ -n "\$\$L1_HASH" ]; then
              break
            fi
            echo "Waiting for L1 genesis... (\$\$i/60)"
            sleep 1
          done

          if [ -z "\$\$L1_HASH" ]; then
            echo "Error: Could not get L1 genesis hash"
            exit 1
          fi

          echo "L1 genesis hash: \$\$L1_HASH"

          # Get L2 genesis hash from the patched genesis
          for i in {1..60}; do
            L2_HASH=\$\$(wget -q -O- http://op-geth:8545 --header='Content-Type: application/json' --post-data='{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' 2>/dev/null | grep -o '"hash":"0x[^"]*"' | cut -d'"' -f4 || true)
            if [ -n "\$\$L2_HASH" ]; then
              break
            fi
            echo "Waiting for L2 genesis... (\$\$i/60)"
            sleep 1
          done

          if [ -z "\$\$L2_HASH" ]; then
            echo "Error: Could not get L2 genesis hash"
            exit 1
          fi

          echo "L2 genesis hash: \$\$L2_HASH"

          # Patch the rollup config using awk to update L1 origin and L2 genesis
          awk -v l1_hash="\$\$L1_HASH" -v l2_hash="\$\$L2_HASH" '
          BEGIN { in_l1 = 0; in_l2 = 0 }
          /"l1"[[:space:]]*:[[:space:]]*\{/ { in_l1 = 1; in_l2 = 0 }
          /"l2"[[:space:]]*:[[:space:]]*\{/ { in_l2 = 1; in_l1 = 0 }
          in_l1 && /"hash"[[:space:]]*:/ {
            sub(/"hash"[[:space:]]*:[[:space:]]*"0x[0-9a-f]*"/, "\"hash\": \"" l1_hash "\"")
          }
          in_l1 && /"number"[[:space:]]*:/ {
            sub(/"number"[[:space:]]*:[[:space:]]*[0-9]*/, "\"number\": 0")
          }
          in_l2 && /"hash"[[:space:]]*:/ {
            sub(/"hash"[[:space:]]*:[[:space:]]*"0x[0-9a-f]*"/, "\"hash\": \"" l2_hash "\"")
          }
          in_l2 && /"number"[[:space:]]*:/ {
            sub(/"number"[[:space:]]*:[[:space:]]*[0-9]*/, "\"number\": 0")
          }
          /\}/ && (in_l1 || in_l2) { in_l1 = 0; in_l2 = 0 }
          { print }
          ' "\$\$ROLLUP_TEMPLATE" > "/op-config/\$\$ROLLUP_OUT"

          echo "✅ Rollup config patched"
        fi

        # Start op-node
        exec op-node \\
          --log.level=INFO \\
          --l2=http://op-geth:8551 \\
          --l2.jwt-secret=/runtime/jwt.hex \\
          --verifier.l1-confs=1 \\
          --rollup.config=/op-config/rollup-${L2_CHAIN_ID}.json \\
          --rpc.addr=0.0.0.0 \\
          --rpc.port=8547 \\
          --rpc.enable-admin \\
          --l1=http://geth:8545 \\
          --l1.rpckind=standard \\
          --l1.beacon=http://lighthouse-bn:5052 \\
          --p2p.disable \\
          --safedb.path=/tmp/op-node-safedb \\
          --altda.enabled=false \\
          --sequencer.enabled \\
          --sequencer.l1-confs=2 \\
          --rollup.l1-chain-config=/op-config/l1-genesis.json
    ports:
      - "9547:8547"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:8547/healthz"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 30s
    networks:
      - snapshot-net

  op-batcher:
    image: us-docker.pkg.dev/oplabs-tools-artifacts/images/op-batcher:v1.16.3
    container_name: snapshot-op-batcher
    depends_on:
      op-node:
        condition: service_healthy
    volumes:
      - ./op:/op-config:ro
    entrypoint: /bin/sh
    command:
      - -c
      - |
        # Extract batcher private key from wallets.json
        BATCHER_KEY=\$\$(cat /op-config/wallets.json | grep -o '"batcherPrivateKey"[[:space:]]*:[[:space:]]*"0x[^"]*"' | cut -d'"' -f4)
        if [ -z "\$\$BATCHER_KEY" ]; then
          echo "Error: Could not extract batcher private key from wallets.json"
          exit 1
        fi
        echo "Starting batcher with key: \$\${BATCHER_KEY:0:10}..."

        exec op-batcher \\
          --l2-eth-rpc=http://op-geth:8545 \\
          --rollup-rpc=http://op-node:8547 \\
          --poll-interval=1s \\
          --sub-safety-margin=6 \\
          --num-confirmations=1 \\
          --safe-abort-nonce-too-low-count=3 \\
          --resubmission-timeout=30s \\
          --rpc.addr=0.0.0.0 \\
          --rpc.port=8548 \\
          --rpc.enable-admin \\
          --max-channel-duration=1 \\
          --l1-eth-rpc=http://geth:8545 \\
          --private-key=\$\$BATCHER_KEY \\
          --data-availability-type=blobs \\
          --altda.enabled=false
    ports:
      - "9548:8548"
    networks:
      - snapshot-net

  op-proposer:
    image: us-docker.pkg.dev/oplabs-tools-artifacts/images/op-proposer:v1.10.2
    container_name: snapshot-op-proposer
    depends_on:
      op-node:
        condition: service_healthy
    volumes:
      - ./op:/op-config:ro
    entrypoint: /bin/sh
    command:
      - -c
      - |
        # Extract proposer private key from wallets.json and game factory from state.json
        PROPOSER_KEY=\$\$(cat /op-config/wallets.json | grep -o '"proposerPrivateKey"[[:space:]]*:[[:space:]]*"0x[^"]*"' | cut -d'"' -f4)
        GAME_FACTORY=\$\$(cat /op-config/state.json | grep -o '"DisputeGameFactoryProxy"[[:space:]]*:[[:space:]]*"0x[^"]*"' | cut -d'"' -f4)

        if [ -z "\$\$PROPOSER_KEY" ]; then
          echo "Error: Could not extract proposer private key from wallets.json"
          exit 1
        fi
        if [ -z "\$\$GAME_FACTORY" ]; then
          echo "Warning: Could not extract game factory address from state.json"
          echo "Warning: Proposer may not work correctly without game factory"
        fi

        echo "Starting proposer with key: \$\${PROPOSER_KEY:0:10}..."
        echo "Game factory: \$\$GAME_FACTORY"

        exec op-proposer \\
          --poll-interval=12s \\
          --rpc.port=8560 \\
          --rollup-rpc=http://op-node:8547 \\
          --game-factory-address=\$\$GAME_FACTORY \\
          --private-key=\$\$PROPOSER_KEY \\
          --l1-eth-rpc=http://geth:8545 \\
          --allow-non-finalized=true \\
          --game-type=1 \\
          --proposal-interval=1m \\
          --wait-node-sync=true
    ports:
      - "9560:8560"
    networks:
      - snapshot-net
COMPOSE_OP_STACK
fi

# Close the compose file
cat >> "$OUTPUT_DIR/docker-compose.yml" <<'COMPOSE_FOOTER'

networks:
  snapshot-net:
    driver: bridge
COMPOSE_FOOTER

if [ "$HAS_OP_STACK" = true ]; then
    echo "Docker compose file created: $OUTPUT_DIR/docker-compose.yml (with OP stack services)"
else
    echo "Docker compose file created: $OUTPUT_DIR/docker-compose.yml (L1 only)"
fi
