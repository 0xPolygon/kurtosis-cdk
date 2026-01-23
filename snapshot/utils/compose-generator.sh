#!/bin/bash
# Helper functions for generating docker-compose service configurations

# Generate L1 Geth service configuration
# Usage: generate_l1_geth_service <image_tag> <chain_id> <log_format> <datadir_path>
generate_l1_geth_service() {
    local image_tag="$1"
    local chain_id="$2"
    local log_format="$3"
    local datadir_path="$4"
    
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
    volumes:
      - ${datadir_path}:/root/.ethereum
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
      - /root/.ethereum/jwtsecret
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
generate_l1_lighthouse_service() {
    local image_tag="$1"
    local log_format="$2"
    local datadir_path="$3"
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
    volumes:
      - ${datadir_path}:/root/.lighthouse
      - ./l1-state/geth/jwtsecret:/root/.ethereum/jwtsecret:ro
    environment:
      - LOG_FORMAT=${log_format}
    depends_on:
      - l1-geth
    command:
      - lighthouse
      - bn
      - --datadir
      - /root/.lighthouse
      - --execution-endpoint
      - http://${geth_service_name}:8551
      - --execution-jwt
      - /root/.ethereum/jwtsecret
      - --disable-optimistic-finalized-sync
      - --disable-backfill-rate-limiting
      - --log-format
      - ${log_format}
      - --http
      - --http-address
      - 0.0.0.0
      - --http-port
      - "4000"
      - --metrics
      - --metrics-address
      - 0.0.0.0
      - --metrics-port
      - "5054"
    restart: unless-stopped
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
    restart: unless-stopped
EOF
    fi
}

# Generate PostgreSQL service configuration
# Usage: generate_postgres_service <network_id> <port_mapping>
generate_postgres_service() {
    local network_id="$1"
    local port_mapping="$2"
    
    local db_port=""
    if [ -n "${port_mapping}" ] && [ "${port_mapping}" != "null" ]; then
        db_port=$(echo "${port_mapping}" | jq -r ".database // 51300" 2>/dev/null || echo "51300")
    fi
    
    if [ -n "${db_port}" ]; then
        local host_port=$((db_port + network_id - 1))
        cat <<EOF
  postgres-${network_id}:
    image: postgres:17.6
    container_name: postgres-${network_id}
    networks:
      - cdk-network
    ports:
      - "${host_port}:5432"
    environment:
      - POSTGRES_USER=master_user
      - POSTGRES_PASSWORD=master_password
      - POSTGRES_DB=master
    volumes:
      - postgres-data-${network_id}:/var/lib/postgresql/data
    restart: unless-stopped
EOF
    else
        cat <<EOF
  postgres-${network_id}:
    image: postgres:17.6
    container_name: postgres-${network_id}
    networks:
      - cdk-network
    environment:
      - POSTGRES_USER=master_user
      - POSTGRES_PASSWORD=master_password
      - POSTGRES_DB=master
    volumes:
      - postgres-data-${network_id}:/var/lib/postgresql/data
    restart: unless-stopped
EOF
    fi
}

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
      - l1-geth
      - l1-lighthouse
      - agglayer
      - postgres-${network_id}
    entrypoint:
      - /usr/local/share/proc-runner/proc-runner.sh
    command:
      - cdk-erigon
      - --config
      - /etc/cdk-erigon/config.yaml
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
      - cdk-erigon-sequencer-${network_id}
    entrypoint:
      - /usr/local/share/proc-runner/proc-runner.sh
    command:
      - cdk-erigon
      - --config
      - /etc/cdk-erigon/config.yaml
    restart: unless-stopped
EOF
}

# Generate CDK-Node service
# Usage: generate_cdk_node_service <network_id> <image> <config_path> <genesis_path> <keystore_dir> <rpc_port> <rest_port> <aggregator_port>
generate_cdk_node_service() {
    local network_id="$1"
    local image="$2"
    local config_path="$3"
    local genesis_path="$4"
    local keystore_dir="$5"
    local rpc_port="$6"
    local rest_port="$7"
    local aggregator_port="$8"
    
    cat <<EOF
  cdk-node-${network_id}:
    image: ${image}
    container_name: cdk-node-${network_id}
    networks:
      - cdk-network
    ports:
      - "${rpc_port}:5576"
      - "${rest_port}:5577"
      - "${aggregator_port}:50081"
    volumes:
      - ${config_path}:/etc/cdk/config.toml:ro
      - ${genesis_path}:/etc/cdk/genesis.json:ro
      - ${keystore_dir}/aggregator.keystore:/etc/cdk/aggregator.keystore:ro
      - ${keystore_dir}/sequencer.keystore:/etc/cdk/sequencer.keystore:ro
      - ${keystore_dir}/claimsponsor.keystore:/etc/cdk/claimsponsor.keystore:ro
      # Empty volume - CDK-Node will sync from L1 on first run
      - cdk-node-data-${network_id}:/data
    depends_on:
      - cdk-erigon-sequencer-${network_id}
      - cdk-erigon-rpc-${network_id}
      - postgres-${network_id}
    entrypoint:
      - sh
      - -c
    command:
      - "sleep 20 && cdk-node --config /etc/cdk/config.toml"
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
            depends_on="${depends_on}
      - ${service}"
        done
    else
        depends_on="    depends_on:
      - postgres-${network_id}"
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
      - postgres-${network_id}
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
      - cdk-node-${network_id}
      - postgres-${network_id}
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
      - postgres-${network_id}
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
    depends_on:
      - postgres-${network_id}
    restart: unless-stopped
EOF
}

# Generate OP-Geth service
# Usage: generate_op_geth_service <network_id> <image> <config_dir> <genesis_path> <http_port> <ws_port>
generate_op_geth_service() {
    local network_id="$1"
    local image="$2"
    local config_dir="$3"
    local genesis_path="$4"
    local http_port="$5"
    local ws_port="$6"
    
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
      - ${config_dir}:/etc/op-geth:ro
      - ${genesis_path}:/etc/op-geth/genesis.json:ro
      # Empty volume - OP-Geth will sync from L1 on first run
      - op-geth-data-${network_id}:/data
    depends_on:
      - l1-geth
      - l1-lighthouse
      - agglayer
      - postgres-${network_id}
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
    
    cat <<EOF
  op-node-${network_id}:
    image: ${image}
    container_name: op-node-${network_id}
    networks:
      - cdk-network
    ports:
      - "${http_port}:8547"
    volumes:
      - ${config_path}:/etc/op-node/config.toml:ro
      # Empty volume - OP-Node will sync from L1 on first run
      - op-node-data-${network_id}:/data
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
      - DATABASE_URL=postgres://op_succinct_user:op_succinct_password@postgres-${network_id}:5432/op_succinct_db
    depends_on:
      - op-geth-${network_id}
      - op-node-${network_id}
      - postgres-${network_id}
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
            echo "  postgres-data-${network_id}:"
            echo "  cdk-erigon-data-${network_id}:"
            echo "  cdk-erigon-rpc-data-${network_id}:"
            echo "  cdk-node-data-${network_id}:"
            echo "  aggkit-data-${network_id}:"
            echo "  aggkit-tmp-${network_id}:"
            echo "  op-geth-data-${network_id}:"
            echo "  op-node-data-${network_id}:"
            echo "  op-proposer-data-${network_id}:"
        fi
    done
}
