#!/bin/bash
# Helper functions for generating docker-compose service configurations

# Generate L1 Geth service configuration
# Usage: generate_l1_geth_service <image_tag> <chain_id> <log_format> <datadir_path>
# Note: datadir_path parameter is kept for backward compatibility but not used
# The Docker image has the state baked in via the Dockerfile COPY command
generate_l1_geth_service() {
    local image_tag="$1"
    local chain_id="$2"
    local log_format="$3"
    local datadir_path="$4"  # Unused - kept for backward compatibility

    cat <<EOF
  l1-geth:
    image: ${image_tag}
    container_name: l1-geth
    networks:
      - cdk-network
    ports:
      - "8545:8545"
      - "8546:8546"
      - "30303:30303/udp"
    environment:
      - CHAIN_ID=${chain_id}
      - LOG_FORMAT=${log_format}
    command:
      - --datadir
      - /root/.ethereum
      - --http
      - --http.addr
      - 0.0.0.0
      - --http.port
      - '8545'
      - --http.api
      - eth,net,web3,engine
      - --ws
      - --ws.addr
      - 0.0.0.0
      - --ws.port
      - '8546'
      - --ws.api
      - eth,net,web3
      - --authrpc.addr
      - 0.0.0.0
      - --authrpc.port
      - '8551'
      - --authrpc.jwtsecret
      - /jwt/jwtsecret
      - --authrpc.vhosts
      - '*'
      - --gcmode
      - archive
      - --log.format
      - ${log_format}
      - --networkid
      - "${chain_id}"
      - --http.corsdomain
      - '*'
      - --http.vhosts
      - '*'
    restart: unless-stopped
EOF
}

# Generate L1 Lighthouse service configuration
# Usage: generate_l1_lighthouse_service <image_tag> <log_format> <datadir_path> <geth_service_name>
# Note: datadir_path parameter is kept for backward compatibility but not used
# The Docker image has the state baked in via the Dockerfile COPY command
generate_l1_lighthouse_service() {
    local image_tag="$1"
    local log_format="$2"
    local datadir_path="$3"  # Unused - kept for backward compatibility
    local geth_service_name="$4"

    cat <<EOF
  l1-lighthouse:
    image: ${image_tag}
    container_name: l1-lighthouse
    networks:
      - cdk-network
    ports:
      - "4000:4000"
      - "9000:9000/udp"
      - "5054:5054"
    environment:
      - LOG_FORMAT=${log_format}
    depends_on:
      - l1-geth
    restart: unless-stopped
    # Note: The lighthouse image already has the full command configured in its ENTRYPOINT,
    # so we don't need to override it here. The ENTRYPOINT includes all necessary flags.
    # The JWT secret is shared between geth and lighthouse images during image build.
EOF
}

# Generate L1 Lighthouse Validator service configuration
# Usage: generate_l1_validator_service <image_tag> <log_format> <beacon_node_url>
generate_l1_validator_service() {
    local image_tag="$1"
    local log_format="$2"
    local beacon_node_url="$3"

    cat <<EOF
  l1-validator:
    image: ${image_tag}
    container_name: l1-validator
    networks:
      - cdk-network
    environment:
      - LOG_FORMAT=${log_format}
      - BEACON_NODE_URL=${beacon_node_url}
    depends_on:
      - l1-lighthouse
    restart: unless-stopped
    # Note: The validator image has keys baked in and uses the same base image as lighthouse
    # Lighthouse will automatically create the slashing protection DB on first run
    entrypoint: ["lighthouse", "vc"]
    command:
      - --datadir
      - /root/.lighthouse
      - --testnet-dir
      - /root/.lighthouse/testnet
      - --beacon-nodes
      - ${beacon_node_url}
      - --suggested-fee-recipient
      - "0x0000000000000000000000000000000000000000"
      - --init-slashing-protection
      - --log-format
      - ${log_format}
EOF
}

# Generate Agglayer service configuration
# Usage: generate_agglayer_service <image> <config_path> <keystore_path> <sp1_prover_key>
generate_agglayer_service() {
    local image="$1"
    local config_path="$2"
    local keystore_path="$3"
    local sp1_prover_key="$4"
    
    if [ -n "${sp1_prover_key}" ] && [ "${sp1_prover_key}" != "null" ]; then
        cat <<EOF
  agglayer:
    image: ${image}
    container_name: agglayer
    networks:
      - cdk-network
    ports:
      - "4443:4443"
      - "4444:4444"
      - "4446:4446"
      - "9092:9092"
    volumes:
      - ${config_path}:/etc/agglayer/config.toml:ro
      - ${keystore_path}:/etc/agglayer/aggregator.keystore:ro
    environment:
      - SP1_PROVER_KEY=${sp1_prover_key}
      - NETWORK_PRIVATE_KEY=${sp1_prover_key}
      - SP1_PRIVATE_KEY=${sp1_prover_key}
      - RUST_BACKTRACE=1
    depends_on:
      - l1-geth
      - l1-lighthouse
    entrypoint:
      - /usr/local/bin/agglayer
    command:
      - run
      - --cfg
      - /etc/agglayer/config.toml
    healthcheck:
      test: ["CMD-SHELL", "timeout 2 bash -c '</dev/tcp/localhost/4444' || exit 1"]
      interval: 3s
      timeout: 3s
      retries: 10
      start_period: 10s
    restart: unless-stopped
EOF
    else
        cat <<EOF
  agglayer:
    image: ${image}
    container_name: agglayer
    networks:
      - cdk-network
    ports:
      - "4443:4443"
      - "4444:4444"
      - "4446:4446"
      - "9092:9092"
    volumes:
      - ${config_path}:/etc/agglayer/config.toml:ro
      - ${keystore_path}:/etc/agglayer/aggregator.keystore:ro
    depends_on:
      - l1-geth
      - l1-lighthouse
    entrypoint:
      - /usr/local/bin/agglayer
    command:
      - run
      - --cfg
      - /etc/agglayer/config.toml
    healthcheck:
      test: ["CMD-SHELL", "timeout 2 bash -c '</dev/tcp/localhost/4444' || exit 1"]
      interval: 3s
      timeout: 3s
      retries: 10
      start_period: 10s
    restart: unless-stopped
EOF
    fi
}

# Note: PostgreSQL is not needed in the snapshot feature.
# AggKit uses SQLite for all its storage needs (not PostgreSQL).
# The generate_postgres_service function has been removed.

# Generate CDK-Erigon sequencer service
# Usage: generate_cdk_erigon_sequencer_service <network_id> <image> <config_dir> <http_port> <ws_port>
generate_cdk_erigon_sequencer_service() {
    local network_id="$1"
    local image="$2"
    local config_dir="$3"
    local http_port="$4"
    local ws_port="$5"

    cat <<EOF
  cdk-erigon-sequencer-${network_id}:
    image: ${image}
    container_name: cdk-erigon-sequencer-${network_id}
    user: "0:0"
    networks:
      - cdk-network
    ports:
      - "${http_port}:8545"
      - "${ws_port}:8546"
    volumes:
      - ${config_dir}:/etc/cdk-erigon:ro
      - ${config_dir}:/home/erigon/dynamic-configs:ro
      # Empty volume - CDK-Erigon will sync from L1 on first run
      - cdk-erigon-data-${network_id}:/home/erigon/data
    environment:
      - CDK_ERIGON_SEQUENCER=1
    depends_on:
      l1-geth:
        condition: service_started
      l1-lighthouse:
        condition: service_started
    entrypoint: ["sh", "-c"]
    command: ["cdk-erigon --config /etc/cdk-erigon/config.yaml"]
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O- --timeout=2 http://localhost:8545 > /dev/null 2>&1 || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 20s
    restart: unless-stopped
EOF
}

# Generate CDK-Erigon RPC service
# Usage: generate_cdk_erigon_rpc_service <network_id> <image> <config_dir> <http_port> <ws_port>
generate_cdk_erigon_rpc_service() {
    local network_id="$1"
    local image="$2"
    local config_dir="$3"
    local http_port="$4"
    local ws_port="$5"

    cat <<EOF
  cdk-erigon-rpc-${network_id}:
    image: ${image}
    container_name: cdk-erigon-rpc-${network_id}
    user: "0:0"
    networks:
      - cdk-network
    ports:
      - "${http_port}:8545"
      - "${ws_port}:8546"
    volumes:
      - ${config_dir}:/etc/cdk-erigon:ro
      - ${config_dir}:/home/erigon/dynamic-configs:ro
      # Empty volume - CDK-Erigon RPC will sync from sequencer on first run
      - cdk-erigon-rpc-data-${network_id}:/home/erigon/data
    environment:
      - CDK_ERIGON_SEQUENCER=0
    depends_on:
      cdk-erigon-sequencer-${network_id}:
        condition: service_healthy
    entrypoint: ["sh", "-c"]
    command: ["cdk-erigon --config /etc/cdk-erigon/config.yaml"]
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O- --timeout=2 http://localhost:8545 > /dev/null 2>&1 || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 20s
    restart: unless-stopped
EOF
}

# Generate AggKit service
# Usage: generate_aggkit_service <network_id> <image> <config_path> <keystore_dir> <components> <depends_on_services>
generate_aggkit_service() {
    local network_id="$1"
    local image="$2"
    local config_path="$3"
    local keystore_dir="$4"
    local components="$5"
    local depends_on_services="$6"

    local depends_on=""
    if [ -n "${depends_on_services}" ]; then
        depends_on="    depends_on:"
        for service in ${depends_on_services}; do
            # Use service_healthy condition for cdk-erigon-rpc and op-node services
            if [[ "${service}" == cdk-erigon-rpc-* ]]; then
                depends_on="${depends_on}
      ${service}:
        condition: service_healthy"
            else
                depends_on="${depends_on}
      - ${service}"
            fi
        done
    fi

    cat <<EOF
  aggkit-${network_id}:
    image: ${image}
    container_name: aggkit-${network_id}
    networks:
      - cdk-network
    volumes:
      - ${config_path}:/etc/aggkit/config.toml:ro
      - ${keystore_dir}/sequencer.keystore:/etc/aggkit/sequencer.keystore:ro
      - ${keystore_dir}/aggregator.keystore:/etc/aggkit/aggregator.keystore:ro
      - ${keystore_dir}/aggoracle.keystore:/etc/aggkit/aggoracle.keystore:ro
      - ${keystore_dir}/claimsponsor.keystore:/etc/aggkit/claimsponsor.keystore:ro
      # Empty volumes - AggKit starts fresh
      - aggkit-data-${network_id}:/data
      - aggkit-tmp-${network_id}:/tmp
${depends_on}
    entrypoint:
      - /usr/local/bin/aggkit
    command:
      - run
      - --cfg=/etc/aggkit/config.toml
      - --components=${components}
    restart: unless-stopped
EOF
}

# Generate Bridge service
# Usage: generate_bridge_service <network_id> <image> <config_path> <keystore_path> <rpc_port> <grpc_port> <metrics_port>
generate_bridge_service() {
    local network_id="$1"
    local image="$2"
    local config_path="$3"
    local keystore_path="$4"
    local rpc_port="$5"
    local grpc_port="$6"
    local metrics_port="$7"
    
    cat <<EOF
  zkevm-bridge-${network_id}:
    image: ${image}
    container_name: zkevm-bridge-${network_id}
    networks:
      - cdk-network
    ports:
      - "${rpc_port}:8080"
      - "${grpc_port}:9090"
      - "${metrics_port}:8090"
    volumes:
      - ${config_path}:/etc/zkevm/bridge-config.toml:ro
      - ${keystore_path}:/etc/zkevm/claimsponsor.keystore:ro
    depends_on:
      - l1-geth
    entrypoint:
      - /app/zkevm-bridge
    command:
      - run
      - --cfg
      - /etc/zkevm/bridge-config.toml
    restart: unless-stopped
EOF
}

# Generate ZKEVM Prover service
# Usage: generate_zkevm_prover_service <network_id> <image> <config_path> <hash_db_port> <executor_port>
generate_zkevm_prover_service() {
    local network_id="$1"
    local image="$2"
    local config_path="$3"
    local hash_db_port="$4"
    local executor_port="$5"
    
    cat <<EOF
  zkevm-prover-${network_id}:
    image: ${image}
    container_name: zkevm-prover-${network_id}
    networks:
      - cdk-network
    ports:
      - "${hash_db_port}:50061"
      - "${executor_port}:50071"
    volumes:
      - ${config_path}:/etc/zkevm-prover/config.json:ro
    depends_on:
      - aggkit-${network_id}
    entrypoint:
      - /bin/bash
      - -c
    command:
      - '[[ "$$(uname -m)" == "aarch64" || "$$(uname -m)" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; /usr/local/bin/zkProver -c /etc/zkevm-prover/config.json'
    restart: unless-stopped
EOF
}

# Generate Pool Manager service
# Usage: generate_pool_manager_service <network_id> <image> <config_path> <http_port>
generate_pool_manager_service() {
    local network_id="$1"
    local image="$2"
    local config_path="$3"
    local http_port="$4"
    
    cat <<EOF
  zkevm-pool-manager-${network_id}:
    image: ${image}
    container_name: zkevm-pool-manager-${network_id}
    networks:
      - cdk-network
    ports:
      - "${http_port}:8545"
    volumes:
      - ${config_path}:/etc/pool-manager/config.toml:ro
    depends_on:
      - cdk-erigon-sequencer-${network_id}
    entrypoint:
      - /bin/sh
      - -c
    command:
      - /app/zkevm-pool-manager run --cfg /etc/pool-manager/config.toml
    restart: unless-stopped
EOF
}

# Generate DAC service
# Usage: generate_dac_service <network_id> <image> <config_path> <port>
generate_dac_service() {
    local network_id="$1"
    local image="$2"
    local config_path="$3"
    local port="$4"
    
    cat <<EOF
  zkevm-dac-${network_id}:
    image: ${image}
    container_name: zkevm-dac-${network_id}
    networks:
      - cdk-network
    ports:
      - "${port}:8080"
    volumes:
      - ${config_path}:/etc/dac/config.toml:ro
    restart: unless-stopped
EOF
}

# Generate OP-Geth service
# Usage: generate_op_geth_service <network_id> <image> <config_dir> <genesis_path> <http_port> <ws_port> <l2_chain_id>
generate_op_geth_service() {
    local network_id="$1"
    local image="$2"
    local config_dir="$3"
    local genesis_path="$4"
    local http_port="$5"
    local ws_port="$6"
    local l2_chain_id="${7:-1}"  # Default to 1 if not provided

    cat <<EOF
  op-geth-${network_id}:
    image: ${image}
    container_name: op-geth-${network_id}
    networks:
      - cdk-network
    ports:
      - "${http_port}:8545"
      - "${ws_port}:8546"
    volumes:
      - ${config_dir}/genesis.json:/genesis.json:ro
      - ${config_dir}/jwt.txt:/jwt.txt:ro
      # Empty volume - OP-Geth will sync from L1 on first run
      - op-geth-data-${network_id}:/data
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        if [ ! -d "/data/geth" ]; then
          echo "Initializing genesis..."
          geth init --datadir=/data /genesis.json
        fi
        echo "Starting geth..."
        exec geth \
          --datadir=/data \
          --http \
          --http.addr=0.0.0.0 \
          --http.port=8545 \
          --http.api=eth,net,web3,debug,txpool \
          --http.corsdomain=* \
          --http.vhosts=* \
          --ws \
          --ws.addr=0.0.0.0 \
          --ws.port=8546 \
          --ws.api=eth,net,web3,debug,txpool \
          --ws.origins=* \
          --authrpc.addr=0.0.0.0 \
          --authrpc.port=8551 \
          --authrpc.vhosts=* \
          --authrpc.jwtsecret=/jwt.txt \
          --networkid=${l2_chain_id} \
          --syncmode=full \
          --gcmode=archive \
          --nodiscover \
          --maxpeers=0 \
          --rollup.disabletxpoolgossip=true \
          --rollup.sequencerhttp=http://op-node-${network_id}:8547
    depends_on:
      - l1-geth
      - l1-lighthouse
      - agglayer
    restart: unless-stopped
EOF
}

# Generate OP-Node service
# Usage: generate_op_node_service <network_id> <image> <config_path> <http_port>
generate_op_node_service() {
    local network_id="$1"
    local image="$2"
    local config_path="$3"
    local http_port="$4"

    # config_path points to config dir (e.g. ./configs/1)
    local config_dir=$(dirname "${config_path}")

    cat <<EOF
  op-node-${network_id}:
    image: ${image}
    container_name: op-node-${network_id}
    networks:
      - cdk-network
    ports:
      - "${http_port}:8547"
    volumes:
      - ${config_dir}/rollup.json:/rollup.json:ro
      - ${config_dir}/jwt.txt:/jwt.txt:ro
      - ./l1-config/genesis.json:/l1-genesis.json:ro
      # Empty volume - OP-Node will sync from L1 on first run
      - op-node-data-${network_id}:/data
    command:
      - op-node
      - --l1=http://l1-geth:8545
      - --l1.beacon=http://l1-lighthouse:4000
      - --rollup.l1-chain-config=/l1-genesis.json
      - --l2=http://op-geth-${network_id}:8545
      - --l2.jwt-secret=/jwt.txt
      - --sequencer.enabled=true
      - --sequencer.l1-confs=4
      - --verifier.l1-confs=4
      - --rollup.config=/rollup.json
      - --rpc.addr=0.0.0.0
      - --rpc.port=8547
      - --p2p.disable
      - --rpc.enable-admin
      - --p2p.sequencer.key=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
      - --log.level=info
    depends_on:
      - op-geth-${network_id}
    restart: unless-stopped
EOF
}

# Generate OP-Proposer service (OP-Succinct)
# Usage: generate_op_proposer_service <network_id> <image> <genesis_path> <grpc_port> <metrics_port>
generate_op_proposer_service() {
    local network_id="$1"
    local image="$2"
    local genesis_path="$3"
    local grpc_port="$4"
    local metrics_port="$5"
    
    cat <<EOF
  op-proposer-${network_id}:
    image: ${image}
    container_name: op-proposer-${network_id}
    networks:
      - cdk-network
    ports:
      - "${grpc_port}:50051"
      - "${metrics_port}:8080"
    volumes:
      - ${genesis_path}:/app/configs/L1:ro
      # Empty volume - OP-Proposer starts fresh
      - op-proposer-data-${network_id}:/data
    environment:
      - L1_RPC=http://l1-geth:8545
      - L1_BEACON_RPC=http://l1-lighthouse:4000
      - L2_RPC=http://op-geth-${network_id}:8545
      - L2_NODE_RPC=http://op-node-${network_id}:8547
    depends_on:
      - op-geth-${network_id}
      - op-node-${network_id}
    restart: unless-stopped
EOF
}

# Generate volumes section
# Usage: generate_volumes <network_ids>
# 
# Note: All L2 data volumes are intentionally empty (named volumes without initialization).
# This is by design - L2 services start fresh and perform initial sync from L1 on first run.
# This keeps snapshots smaller and simpler, as no L2 state is captured or extracted.
# Services will sync from L1 automatically when they start for the first time.
generate_volumes() {
    local network_ids="$1"
    
    if [ -z "${network_ids}" ]; then
        return
    fi
    
    echo "  # L2 Data Volumes"
    echo "  # Note: These volumes start empty. L2 services will sync from L1 on first run."
    for network_id in ${network_ids}; do
        if [ -n "${network_id}" ] && [ "${network_id}" != "null" ]; then
            echo "  cdk-erigon-data-${network_id}:"
            echo "  cdk-erigon-rpc-data-${network_id}:"
            echo "  aggkit-data-${network_id}:"
            echo "  aggkit-tmp-${network_id}:"
            echo "  op-geth-data-${network_id}:"
            echo "  op-node-data-${network_id}:"
            echo "  op-proposer-data-${network_id}:"
        fi
    done
}
