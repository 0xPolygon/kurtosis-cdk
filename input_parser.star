constants = import_module("./src/package_io/constants.star")
dict = import_module("./src/package_io/dict.star")

# The deployment process is divided into various stages.
# You can deploy the whole stack and then only deploy a subset of the components to perform an
# an upgrade or to test a new version of a component.
DEFAULT_DEPLOYMENT_STAGES = {
    # Deploy a local L1 chain using the ethereum-package.
    # Set to false to use an external L1 like Sepolia.
    # Note that it will require a few additional parameters.
    "deploy_l1": True,
    # Deploy zkevm contracts on L1 (as well as fund accounts).
    # Set to false to use pre-deployed zkevm contracts.
    # Note that it will require a few additional parameters.
    "deploy_zkevm_contracts_on_l1": True,
    # Deploy databases.
    "deploy_databases": True,
    # Deploy CDK central/trusted environment.
    "deploy_cdk_central_environment": True,
    # Deploy CDK bridge infrastructure.
    "deploy_cdk_bridge_infra": True,
    # Deploy CDK bridge UI.
    "deploy_cdk_bridge_ui": True,
    # Deploy the agglayer.
    "deploy_agglayer": True,
    # Deploy cdk-erigon node.
    # TODO: Remove this parameter to incorporate cdk-erigon inside the central environment.
    "deploy_cdk_erigon_node": True,
    # Deploy Optimism rollup.
    # Note the default behavior will only deploy the OP Stack without CDK Erigon stack.
    # Setting to True will deploy the Aggkit components and Sovereign contracts as well.
    # Requires consensus_contract_type to be "pessimistic".
    "deploy_optimism_rollup": False,
    # After deploying OP Stack, upgrade it to OP Succinct.
    # Even mock-verifier deployments require an actual SPN network key.
    "deploy_op_succinct": False,
    # Deploy contracts on L2 (as well as fund accounts).
    "deploy_l2_contracts": False,
}

DEFAULT_IMAGES = {
    "aggkit_image": "ghcr.io/agglayer/aggkit:0.1.0-beta4",  # https://github.com/agglayer/aggkit/pkgs/container/aggkit
    "agglayer_image": "ghcr.io/agglayer/agglayer:0.3.0-rc.5",  # https://github.com/agglayer/agglayer/tags
    "cdk_erigon_node_image": "hermeznetwork/cdk-erigon:v2.61.19",  # https://hub.docker.com/r/hermeznetwork/cdk-erigon/tags
    "cdk_node_image": "ghcr.io/0xpolygon/cdk:0.5.3-rc1",  # https://github.com/0xpolygon/cdk/pkgs/container/cdk
    "cdk_validium_node_image": "ghcr.io/0xpolygon/cdk-validium-node:0.6.4-cdk.10",  # https://github.com/0xPolygon/cdk-validium-node/pkgs/container/cdk-validium-node/
    "zkevm_bridge_proxy_image": "haproxy:3.1-bookworm",  # https://hub.docker.com/_/haproxy/tags
    "zkevm_bridge_service_image": "hermeznetwork/zkevm-bridge-service:v0.6.0-RC15",  # https://hub.docker.com/r/hermeznetwork/zkevm-bridge-service/tags
    "zkevm_bridge_ui_image": "leovct/zkevm-bridge-ui:multi-network",  # https://hub.docker.com/r/leovct/zkevm-bridge-ui/tags
    "zkevm_da_image": "ghcr.io/0xpolygon/cdk-data-availability:0.0.13",  # https://github.com/0xpolygon/cdk-data-availability/pkgs/container/cdk-data-availability
    "zkevm_contracts_image": "leovct/zkevm-contracts:v10.0.0-rc.3-fork.12",  # https://hub.docker.com/repository/docker/leovct/zkevm-contracts/tags
    "zkevm_node_image": "hermeznetwork/zkevm-node:v0.7.3",  # https://hub.docker.com/r/hermeznetwork/zkevm-node/tags
    "zkevm_pool_manager_image": "hermeznetwork/zkevm-pool-manager:v0.1.2",  # https://hub.docker.com/r/hermeznetwork/zkevm-pool-manager/tags
    "zkevm_prover_image": "hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12",  # https://hub.docker.com/r/hermeznetwork/zkevm-prover/tags
    "zkevm_sequence_sender_image": "hermeznetwork/zkevm-sequence-sender:v0.2.4",  # https://hub.docker.com/r/hermeznetwork/zkevm-sequence-sender/tags
    "anvil_image": "ghcr.io/foundry-rs/foundry:v1.0.0",  # https://github.com/foundry-rs/foundry/pkgs/container/foundry/versions?filters%5Bversion_type%5D=tagged
    "mitm_image": "mitmproxy/mitmproxy:11.1.3",  # https://hub.docker.com/r/mitmproxy/mitmproxy/tags
    "op_succinct_contract_deployer_image": "jhkimqd/op-succinct-contract-deployer:v0.0.4-agglayer",  # https://hub.docker.com/r/jhkimqd/op-succinct-contract-deployer
    "op_succinct_server_image": "ghcr.io/succinctlabs/op-succinct/succinct-proposer:sha-cb18ac0",  # https://github.com/succinctlabs/op-succinct/pkgs/container/op-succinct%2Fsuccinct-proposer
    "op_succinct_proposer_image": "ghcr.io/succinctlabs/op-succinct/op-proposer:sha-cb18ac0",  # https://github.com/succinctlabs/op-succinct/pkgs/container/op-succinct%2Fop-proposer
}

DEFAULT_PORTS = {
    "agglayer_grpc_port": 4443,
    "agglayer_readrpc_port": 4444,
    "agglayer_prover_port": 4445,
    "agglayer_admin_port": 4446,
    "agglayer_metrics_port": 9092,
    "agglayer_prover_metrics_port": 9093,
    "prometheus_port": 9091,
    "zkevm_aggregator_port": 50081,
    "zkevm_bridge_grpc_port": 9090,
    "zkevm_bridge_rpc_port": 8080,
    "zkevm_bridge_ui_port": 80,
    "zkevm_bridge_metrics_port": 8090,
    "zkevm_dac_port": 8484,
    "zkevm_data_streamer_port": 6900,
    "zkevm_executor_port": 50071,
    "zkevm_hash_db_port": 50061,
    "zkevm_pool_manager_port": 8545,
    "zkevm_pprof_port": 6060,
    "zkevm_rpc_http_port": 8123,
    "zkevm_rpc_ws_port": 8133,
    "zkevm_cdk_node_port": 5576,
    "blockscout_frontend_port": 3000,
    "anvil_port": 8545,
    "mitm_port": 8234,
    "op_succinct_server_port": 3000,
    "op_succinct_proposer_port": 7300,
}

DEFAULT_STATIC_PORTS = {
    "static_ports": {
        ## L1 static ports (50000-50999).
        "l1_el_start_port": 50000,
        "l1_cl_start_port": 50010,
        "l1_vc_start_port": 50020,
        "l1_additional_services_start_port": 50100,
        ## L2 static ports (51000-51999).
        # Agglayer (51000-51099).
        "agglayer_start_port": 51000,
        "agglayer_prover_start_port": 51010,
        # CDK node (51100-51199).
        "cdk_node_start_port": 51100,
        # Bridge services (51200-51299).
        "zkevm_bridge_service_start_port": 51200,
        "zkevm_bridge_ui_start_port": 51210,
        "reverse_proxy_start_port": 51220,
        # Databases (51300-51399).
        "database_start_port": 51300,
        "pless_database_start_port": 51310,
        # Pool manager (51400-51499).
        "zkevm_pool_manager_start_port": 51400,
        # DAC (51500-51599).
        "zkevm_dac_start_port": 51500,
        # ZkEVM Provers (51600-51699).
        "zkevm_prover_start_port": 51600,
        "zkevm_executor_start_port": 51610,
        "zkevm_stateless_executor_start_port": 51620,
        # CDK erigon (51700-51799).
        "cdk_erigon_sequencer_start_port": 51700,
        "cdk_erigon_rpc_start_port": 51710,
        # L2 additional services (52000-52999).
        "arpeggio_start_port": 52000,
        "blutgang_start_port": 52010,
        "erpc_start_port": 52020,
        "panoptichain_start_port": 52030,
    }
}

# Addresses and private keys of the different components.
# They have been generated using the following command:
# polycli wallet inspect --mnemonic 'lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop' --addresses 14 | tee keys.txt | jq -r '.Addresses[] | [.ETHAddress, .HexPrivateKey] | @tsv' | awk 'BEGIN{split("sequencer,aggregator,claimtxmanager,timelock,admin,loadtest,agglayer,dac,proofsigner,l1testing,claimsponsor,aggoracle,sovereignadmin",roles,",")} {print "# " roles[NR] "\n\"zkevm_l2_" roles[NR] "_address\": \"" $1 "\","; print "\"zkevm_l2_" roles[NR] "_private_key\": \"0x" $2 "\",\n"}'
DEFAULT_ACCOUNTS = {
    # sequencer
    "zkevm_l2_sequencer_address": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
    "zkevm_l2_sequencer_private_key": "0x183c492d0ba156041a7f31a1b188958a7a22eebadca741a7fe64436092dc3181",
    # aggregator
    "zkevm_l2_aggregator_address": "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
    "zkevm_l2_aggregator_private_key": "0x2857ca0e7748448f3a50469f7ffe55cde7299d5696aedd72cfe18a06fb856970",
    # claimtxmanager
    "zkevm_l2_claimtxmanager_address": "0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8",
    "zkevm_l2_claimtxmanager_private_key": "0x8d5c9ecd4ba2a195db3777c8412f8e3370ae9adffac222a54a84e116c7f8b934",
    # timelock
    "zkevm_l2_timelock_address": "0x130aA39Aa80407BD251c3d274d161ca302c52B7A",
    "zkevm_l2_timelock_private_key": "0x80051baf5a0a749296b9dcdb4a38a264d2eea6d43edcf012d20b5560708cf45f",
    # admin
    "zkevm_l2_admin_address": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
    "zkevm_l2_admin_private_key": "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625",
    # loadtest
    "zkevm_l2_loadtest_address": "0x81457240ff5b49CaF176885ED07e3E7BFbE9Fb81",
    "zkevm_l2_loadtest_private_key": "0xd7df6d64c569ffdfe7c56e6b34e7a2bdc7b7583db74512a9ffe26fe07faaa5de",
    # agglayer
    "zkevm_l2_agglayer_address": "0x351e560852ee001d5D19b5912a269F849f59479a",
    "zkevm_l2_agglayer_private_key": "0x1d45f90c0a9814d8b8af968fa0677dab2a8ff0266f33b136e560fe420858a419",
    # dac
    "zkevm_l2_dac_address": "0x5951F5b2604c9B42E478d5e2B2437F44073eF9A6",
    "zkevm_l2_dac_private_key": "0x85d836ee6ea6f48bae27b31535e6fc2eefe056f2276b9353aafb294277d8159b",
    # proofsigner
    "zkevm_l2_proofsigner_address": "0x7569cc70950726784c8D3bB256F48e43259Cb445",
    "zkevm_l2_proofsigner_private_key": "0x77254a70a02223acebf84b6ed8afddff9d3203e31ad219b2bf900f4780cf9b51",
    # l1testing
    "zkevm_l2_l1testing_address": "0xfa291C5f54E4669aF59c6cE1447Dc0b3371EF046",
    "zkevm_l2_l1testing_private_key": "0x1324200455e437cd9d9dc4aa61c702f06fb5bc495dc8ad94ae1504107a216b59",
    # claimsponsor
    "zkevm_l2_claimsponsor_address": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    "zkevm_l2_claimsponsor_private_key": "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    # AggKit Addresses
    "zkevm_l2_aggoracle_address": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
    "zkevm_l2_aggoracle_private_key": "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0",
    "zkevm_l2_sovereignadmin_address": "0x635243A11B41072264Df6c9186e3f473402F94e9",
    "zkevm_l2_sovereignadmin_private_key": "0x986b325f6f855236b0b04582a19fe0301eeecb343d0f660c61805299dbf250eb",
}

DEFAULT_L1_ARGS = {
    # The L1 engine to use, either "geth" or "anvil".
    "l1_engine": "geth",
    # The L1 network identifier.
    "l1_chain_id": 271828,
    # This mnemonic will:
    # a) be used to create keystores for all the types of validators that we have, and
    # b) be used to generate a CL genesis.ssz that has the children validator keys already
    # preregistered as validators
    "l1_preallocated_mnemonic": "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete",
    # The L1 HTTP RPC endpoint.
    "l1_rpc_url": "http://el-1-geth-lighthouse:8545",
    # The L1 WS RPC endpoint.
    "l1_ws_url": "ws://el-1-geth-lighthouse:8546",
    # The L1 concensus layer RPC endpoint.
    "l1_beacon_url": "http://cl-1-lighthouse-geth:4000",
    # The additional services to spin up.
    # Default: []
    # Options:
    #   - assertoor
    #   - broadcaster
    #   - tx_spammer
    #   - bridge_spammer
    #   - blob_spammer
    #   - custom_flood
    #   - goomy_blob
    #   - el_forkmon
    #   - blockscout
    #   - beacon_metrics_gazer
    #   - dora
    #   - full_beaconchain_explorer
    #   - prometheus_grafana
    #   - blobscan
    #   - dugtrio
    #   - blutgang
    #   - forky
    #   - apache
    #   - tracoor
    # Check the ethereum-package for more details: https://github.com/ethpandaops/ethereum-package
    "l1_additional_services": [],
    # Preset for the network.
    # Default: "mainnet"
    # Options:
    #   - mainnet
    #   - minimal
    # "minimal" preset will spin up a network with minimal preset. This is useful for rapid testing and development.
    # 192 seconds to get to finalized epoch vs 1536 seconds with mainnet defaults
    # Please note that minimal preset requires alternative client images.
    "l1_preset": "minimal",
    # Number of seconds per slot on the Beacon chain
    # Default: 12
    "l1_seconds_per_slot": 2,
    # Enable the Electra hardfork.
    "pectra_enabled": False,
    # The amount of ETH sent to the admin, sequence, aggregator, sequencer and other chosen addresses.
    "l1_funding_amount": "1000000ether",
    # Default: 2
    "l1_participants_count": 1,
    # Whether to deploy https://github.com/AggLayer/lxly-bridge-and-call
    "l1_deploy_lxly_bridge_and_call": True,
    # Anvil: l1_anvil_slots_in_epoch will set the gap of blocks finalized vs safe vs latest
    #   l1_anvil_block_time * l1_anvil_slots_in_epoch -> total seconds to transition a block from latest to safe
    # l1_anvil_block_time: seconds per block
    "l1_anvil_block_time": 1,
    # l1_anvil_slots_in_epoch: number of slots in an epoch
    "l1_anvil_slots_in_epoch": 1,
    # Set this to true if the L1 contracts for the rollup are already
    # deployed. This also means that you'll need some way to run
    # recovery from outside of kurtosis
    # TODO at some point it would be nice if erigon could recover itself, but this is not going to be easy if there's a DAC
    "use_previously_deployed_contracts": False,
    "erigon_datadir_archive": None,
    "anvil_state_file": None,
    "mitm_proxied_components": {
        "agglayer": False,
        "aggkit": False,
        "bridge": False,
        "dac": False,
        "erigon-sequencer": False,
        "erigon-rpc": False,
        "cdk-node": False,
    },
}

DEFAULT_L2_ARGS = {
    # The number of accounts to fund on L2. The accounts will be derived from:
    # polycli wallet inspect --mnemonic '{{.l1_preallocated_mnemonic}}'
    "l2_accounts_to_fund": 10,
    # The amount of ETH sent to each of the prefunded l2 accounts.
    "l2_funding_amount": "100ether",
    # Whether to deploy https://github.com/Arachnid/deterministic-deployment-proxy.
    # Not deploying this will may cause errors or short circuit other contract
    # deployments.
    "l2_deploy_deterministic_deployment_proxy": True,
    # Whether to deploy https://github.com/AggLayer/lxly-bridge-and-call
    "l2_deploy_lxly_bridge_and_call": True,
    # This is used by erigon for naming the config files
    "chain_name": "kurtosis",
    # Config name for OP stack rollup
    "sovereign_chain_name": "op-sovereign",
}

DEFAULT_ROLLUP_ARGS = {
    # The keystore password.
    "zkevm_l2_keystore_password": "pSnv6Dh5s9ahuzGzH9RoCDrKAMddaX3m",
    # The rollup network identifier.
    "zkevm_rollup_chain_id": 10101,
    # The unique identifier for the rollup within the RollupManager contract.
    # This setting sets the rollup as the first rollup.
    "zkevm_rollup_id": 1,
    # By default a mock verifier is deployed.
    # Change to true to deploy a real verifier which will require a real prover.
    # Note: This will require a lot of memory to run!
    "zkevm_use_real_verifier": False,
    # If we're using pessimistic consensus and a real verifier, we'll
    # need to know which vkey to use. This value is tightly coupled to
    # the agglayer version that's being used
    "verifier_program_vkey": "0x0062c685702e0582d900f3a19521270c92a58e2588230c4a5cf3b45103f4a512",
    # This flag will enable a stateless executor to verify the execution of the batches.
    # Set to true to run erigon as the sequencer.
    "erigon_strict_mode": True,
    # Set to true to use an L1 ERC20 contract as the gas token on the rollup.
    # The address of the gas token will be determined by the value of `gas_token_address`.
    "gas_token_enabled": False,
    # The address of the L1 ERC20 contract that will be used as the gas token on the rollup.
    # If the address is empty, a contract will be deployed automatically.
    # This value will also be used for sovereignWETHAddress parameter in the Sovereign rollup.
    # Default value is 0x0000000000000000000000000000000000000000
    "gas_token_address": "0x0000000000000000000000000000000000000000",
    # Set to true to use Kurtosis dynamic ports (default) and set to false to use static ports.
    # You can either use the default static ports defined in this file or specify your custom static
    # ports.
    #
    # By default, Kurtosis binds the ports of enclave services to ephemeral or dynamic ports on the
    # host machine. To quote the Kurtosis documentation: "these ephemeral ports are called the
    # "public ports" of the container because they allow the container to be accessed outside the
    # Docker/Kubernetes cluster".
    # https://docs.kurtosis.com/advanced-concepts/public-and-private-ips-and-ports/
    "use_dynamic_ports": True,
    # Set this to true to disable all special logics in hermez and only enable bridge update in pre-block execution
    # https://hackmd.io/@4cbvqzFdRBSWMHNeI8Wbwg/r1hKHp_S0
    "enable_normalcy": False,
    # If the agglayer is going to be configured to use SP1 services, we'll need to provide an API Key
    "agglayer_prover_sp1_key": None,
    # If we're setting an sp1 key, we might want to specify a specific RPC url as well
    "agglayer_prover_network_url": "https://rpc.production.succinct.xyz",
    # The type of primary prover to use in agglayer-prover. Note: if mock-prover is selected,
    # agglayer-node will also be configured with a mock verifier
    "agglayer_prover_primary_prover": "mock-prover",
    # The URL where the agglayer can be reached for gRPC
    "agglayer_grpc_url": "http://agglayer:"
    + str(DEFAULT_PORTS.get("agglayer_grpc_port")),
    # The URL where the agglayer can be reached for ReadRPC
    "agglayer_readrpc_url": "http://agglayer:"
    + str(DEFAULT_PORTS.get("agglayer_readrpc_port")),
    # This is a path where the cdk-node will write data
    # https://github.com/0xPolygon/cdk/blob/d0e76a3d1361158aa24135f25d37ecc4af959755/config/default.go#L50
    "zkevm_path_rw_data": "/tmp/",
    # OP Stack EL RPC URL. Will be dynamically updated by args_sanity_check() function.
    "op_el_rpc_url": "http://op-el-1-op-geth-op-node-001:8545",
    # OP Stack CL Node URL. Will be dynamically updated by args_sanity_check() function.
    "op_cl_rpc_url": "http://op-cl-1-op-node-op-geth-001:8547",
    # If the OP Succinct will use the Network Prover or CPU(Mock) Prover
    # true = mock
    # false = network
    "op_succinct_mock": False,
}

DEFAULT_PLESS_ZKEVM_NODE_ARGS = {
    "trusted_sequencer_node_uri": "zkevm-node-sequencer-001:6900",
    "zkevm_aggregator_host": "zkevm-node-aggregator-001",
    "genesis_file": "templates/permissionless-node/genesis.json",
    "sovereign_genesis_file": "templates/sovereign-genesis.json",
}

DEFAULT_ADDITIONAL_SERVICES_PARAMS = {
    "blockscout_params": {
        "blockscout_public_port": DEFAULT_PORTS.get("blockscout_frontend_port"),
    },
}

DEFAULT_ARGS = (
    {
        # Suffix appended to service names.
        # Note: It should be a string.
        "deployment_suffix": "-001",
        # Verbosity of the `kurtosis run` output.
        # Valid values are "error", "warn", "info", "debug", and "trace".
        # By default, the verbosity is set to "info". It won't log the value of the args.
        "verbosity": "info",
        # The global log level that all components of the stack should log at.
        # Valid values are "error", "warn", "info", "debug", and "trace".
        "global_log_level": "info",
        # The type of the sequencer to deploy.
        # Options:
        # - 'erigon': Use the new sequencer (https://github.com/0xPolygonHermez/cdk-erigon).
        # - 'zkevm': Use the legacy sequencer (https://github.com/0xPolygonHermez/zkevm-node).
        "sequencer_type": "erigon",
        # The type of consensus contract to use.
        # Options:
        # - 'rollup': Transaction data is stored on-chain on L1.
        # - 'cdk-validium': Transaction data is stored off-chain using the CDK DA layer and a DAC.
        # - 'pessimistic': deploy with pessimistic consensus
        "consensus_contract_type": "cdk-validium",
        # Additional services to run alongside the network.
        # Options:
        # - arpeggio
        # - assertoor
        # - blockscout
        # - blutgang
        # - bridge_spammer
        # - erpc
        # - pless_zkevm_node
        # - prometheus_grafana
        # - status_checker
        # - tx_spammer
        "additional_services": [],
        # Only relevant when deploying to an external L1.
        "polygon_zkevm_explorer": "https://explorer.private/",
        "l1_explorer_url": "https://sepolia.etherscan.io/",
    }
    | DEFAULT_IMAGES
    | DEFAULT_PORTS
    | DEFAULT_ACCOUNTS
    | DEFAULT_L1_ARGS
    | DEFAULT_ROLLUP_ARGS
    | DEFAULT_PLESS_ZKEVM_NODE_ARGS
    | DEFAULT_L2_ARGS
    | DEFAULT_ADDITIONAL_SERVICES_PARAMS
)

# https://github.com/ethpandaops/optimism-package
# The below OP params can be customized by specifically referring to an artifact or image.
# If none is is provided, it will refer to the default images from the Optimism-Package repo.
# https://github.com/ethpandaops/optimism-package/blob/main/src/package_io/input_parser.star
DEFAULT_OP_STACK_ARGS = {
    "source": "github.com/ethpandaops/optimism-package/main.star@884f4eb813884c4c8e5deead6ca4e0c54b85da90",
    "predeployed_contracts": False,
    "chains": [
        {
            "participants": [
                {
                    # OP Rollup configuration
                    "el_type": "op-geth",
                    "el_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101500.0-rc.3",
                    "cl_type": "op-node",
                    "cl_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.11.0-rc.2",
                    "count": 1,
                },
            ],
            "network_params": {
                # name maps to l2_services_suffix in optimism. The optimism-package appends a suffix with the following format: -<name>
                # the "-" however adds another "-" to the Kurtosis deployment_suffix. So we are doing string manipulation to remove the "-"
                "name": DEFAULT_ARGS.get("deployment_suffix")[1:],
                "network_id": str(DEFAULT_ROLLUP_ARGS.get("zkevm_rollup_chain_id")),
                # The blocktime on the OP network
                "seconds_per_slot": 1,
            },
        },
    ],
}

# A list of fork identifiers currently supported by Kurtosis CDK.
SUPPORTED_FORK_IDS = [9, 11, 12, 13]


def parse_args(plan, user_args):
    # Merge the provided args with defaults.
    deployment_stages = DEFAULT_DEPLOYMENT_STAGES | user_args.get(
        "deployment_stages", {}
    )
    op_stack_args = user_args.get("optimism_package", {})
    args = DEFAULT_ARGS | user_args.get("args", {})

    # Change some params if anvil set to make it work
    # As it changes L1 config it needs to be run before other functions/checks
    set_anvil_args(plan, args, user_args)

    # Determine OP stack args.
    op_stack_args = get_op_stack_args(plan, args, op_stack_args)

    # Sanity check step for incompatible parameters
    args_sanity_check(plan, deployment_stages, args, user_args, op_stack_args)

    # Setting mitm for each element set to true on mitm dict
    mitm_rpc_url = (
        "http://mitm"
        + args["deployment_suffix"]
        + ":"
        + str(DEFAULT_PORTS.get("mitm_port"))
    )
    args["mitm_rpc_url"] = {
        k: mitm_rpc_url for k, v in args.get("mitm_proxied_components", {}).items() if v
    }

    # Validation step.
    verbosity = args.get("verbosity", "")
    validate_log_level("verbosity", verbosity)

    global_log_level = args.get("global_log_level", "")
    validate_log_level("global log level", global_log_level)

    # Determine fork id from the zkevm contracts image tag.
    zkevm_contracts_image = args.get("zkevm_contracts_image", "")
    (fork_id, fork_name) = get_fork_id(zkevm_contracts_image)

    # Determine sequencer and l2 rpc names.
    sequencer_type = args.get("sequencer_type", "")
    sequencer_name = get_sequencer_name(sequencer_type)

    deploy_cdk_erigon_node = deployment_stages.get("deploy_cdk_erigon_node", False)
    l2_rpc_name = get_l2_rpc_name(deploy_cdk_erigon_node)

    # Determine static ports, if specified.
    if not args.get("use_dynamic_ports", True):
        plan.print("Using static ports.")
        args = DEFAULT_STATIC_PORTS | args

    # When using assertoor to test L1 scenarios, l1_preset should be mainnet for deposits and withdrawls to work.
    if "assertoor" in args["l1_additional_services"]:
        plan.print(
            "Assertoor is detected - changing l1_preset to mainnet and l1_participant_count to 2"
        )
        args["l1_preset"] = "mainnet"
        args["l1_participant_count"] = 2

    # Remove deployment stages from the args struct.
    # This prevents updating already deployed services when updating the deployment stages.
    if "deployment_stages" in args:
        args.pop("deployment_stages")

    args = args | {
        "l2_rpc_name": l2_rpc_name,
        "sequencer_name": sequencer_name,
        "zkevm_rollup_fork_id": fork_id,
        "zkevm_rollup_fork_name": fork_name,
        "deploy_agglayer": deployment_stages.get(
            "deploy_agglayer", False
        ),  # hacky but works fine for now.
    }

    # Sort dictionaries for debug purposes.
    sorted_deployment_stages = dict.sort_dict_by_values(deployment_stages)
    sorted_args = dict.sort_dict_by_values(args)
    sorted_op_stack_args = dict.sort_dict_by_values(op_stack_args)
    return (sorted_deployment_stages, sorted_args, sorted_op_stack_args)


def validate_log_level(name, log_level):
    if log_level not in (
        constants.LOG_LEVEL.error,
        constants.LOG_LEVEL.warn,
        constants.LOG_LEVEL.info,
        constants.LOG_LEVEL.debug,
        constants.LOG_LEVEL.trace,
    ):
        fail(
            "Unsupported {}: '{}', please use '{}', '{}', '{}', '{}' or '{}'".format(
                name,
                log_level,
                constants.LOG_LEVEL.error,
                constants.LOG_LEVEL.warn,
                constants.LOG_LEVEL.info,
                constants.LOG_LEVEL.debug,
                constants.LOG_LEVEL.trace,
            )
        )


def get_fork_id(zkevm_contracts_image):
    """
    Extract the fork identifier and fork name from a zkevm contracts image name.

    The zkevm contracts tags follow the convention:
    v<SEMVER>-rc.<RC_NUMBER>-fork.<FORK_ID>[-patch.<PATCH_NUMBER>]

    Where:
    - <SEMVER> is the semantic versioning (MAJOR.MINOR.PATCH).
    - <RC_NUMBER> is the release candidate number.
    - <FORK_ID> is the fork identifier.
    - -patch.<PATCH_NUMBER> is optional and represents the patch number.

    Example:
    - v8.0.0-rc.2-fork.12
    - v7.0.0-rc.1-fork.10
    - v7.0.0-rc.1-fork.11-patch.1
    """
    result = zkevm_contracts_image.split("-patch.")[0].split("-fork.")
    if len(result) != 2:
        fail(
            "The zkevm contracts image tag '{}' does not follow the standard v<SEMVER>-rc.<RC_NUMBER>-fork.<FORK_ID>".format(
                zkevm_contracts_image
            )
        )

    fork_id = int(result[1])
    if fork_id not in SUPPORTED_FORK_IDS:
        fail("The fork id '{}' is not supported by Kurtosis CDK".format(fork_id))

    fork_name = "elderberry"
    if fork_id >= 12:
        fork_name = "banana"
    # TODO: Add support for durian once released.

    return (fork_id, fork_name)


def get_sequencer_name(sequencer_type):
    if sequencer_type == constants.SEQUENCER_TYPE.CDK_ERIGON:
        return "cdk-erigon-sequencer"
    elif sequencer_type == constants.SEQUENCER_TYPE.ZKEVM:
        return "zkevm-node-sequencer"
    else:
        fail(
            "Unsupported sequencer type: '{}', please use '{}' or '{}'".format(
                sequencer_type,
                constants.SEQUENCER_TYPE.CDK_ERIGON,
                constants.SEQUENCER_TYPE.ZKEVM,
            )
        )


def get_l2_rpc_name(deploy_cdk_erigon_node):
    if deploy_cdk_erigon_node:
        return "cdk-erigon-rpc"
    else:
        return "zkevm-node-rpc"


def get_op_stack_args(plan, args, user_op_stack_args):
    op_stack_args = DEFAULT_OP_STACK_ARGS | user_op_stack_args

    l1_chain_id = str(args.get("l1_chain_id", ""))
    l1_rpc_url = args.get("l1_rpc_url", "")
    l1_ws_url = args.get("l1_ws_url", "")
    l1_beacon_url = args.get("l1_beacon_url", "")

    l1_preallocated_mnemonic = args.get("l1_preallocated_mnemonic", "")
    private_key_result = plan.run_sh(
        description="Deriving the private key from the mnemonic",
        run="cast wallet private-key --mnemonic \"{}\" | tr -d '\n'".format(
            l1_preallocated_mnemonic
        ),
        image=constants.TOOLBOX_IMAGE,
    )
    private_key = private_key_result.output

    source = op_stack_args.pop("source")
    predeployed_contracts = op_stack_args.pop("predeployed_contracts")

    return {
        "source": source,
        "predeployed_contracts": predeployed_contracts,
        "optimism_package": op_stack_args,
        "external_l1_network_params": {
            "network_id": l1_chain_id,
            "rpc_kind": "standard",
            "el_rpc_url": l1_rpc_url,
            "el_ws_url": l1_ws_url,
            "cl_rpc_url": l1_beacon_url,
            "priv_key": private_key,
        },
    }


def set_anvil_args(plan, args, user_args):
    if args["anvil_state_file"] != None:
        if user_args.get("args", {}).get("l1_engine") != "anvil":
            args["l1_engine"] = "anvil"
            plan.print("Anvil state file detected - changing l1_engine to anvil")

    if args["l1_engine"] == "anvil":
        # We override only is user did not provide explicit values
        if not user_args.get("args", {}).get("l1_rpc_url"):
            args["l1_rpc_url"] = (
                "http://anvil"
                + args["deployment_suffix"]
                + ":"
                + str(DEFAULT_PORTS.get("anvil_port"))
            )
        if not user_args.get("args", {}).get("l1_ws_url"):
            args["l1_ws_url"] = (
                "ws://anvil"
                + args["deployment_suffix"]
                + ":"
                + str(DEFAULT_PORTS.get("anvil_port"))
            )
        if not user_args.get("args", {}).get("l1_beacon_url"):
            args["l1_beacon_url"] = (
                "http://anvil"
                + args["deployment_suffix"]
                + ":"
                + str(DEFAULT_PORTS.get("anvil_port"))
            )


# Helper function to compact together checks for incompatible parameters in input_parser.star
def args_sanity_check(plan, deployment_stages, args, user_args, op_stack_args):
    # Fix the op stack el rpc urls according to the deployment_suffix.
    if args["op_el_rpc_url"] != "http://op-el-1-op-geth-op-node" + args[
        "deployment_suffix"
    ] + ":8545" and deployment_stages.get("deploy_op_stack", False):
        plan.print(
            "op_el_rpc_url is set to '{}', changing to 'http://op-el-1-op-geth-op-node{}:8545'".format(
                args["op_el_rpc_url"], args["deployment_suffix"]
            )
        )
        args["op_el_rpc_url"] = (
            "http://op-el-1-op-geth-op-node" + args["deployment_suffix"] + ":8545"
        )
    # Fix the op stack cl rpc urls according to the deployment_suffix.
    if args["op_cl_rpc_url"] != "http://op-cl-1-op-node-op-geth" + args[
        "deployment_suffix"
    ] + ":8547" and deployment_stages.get("deploy_op_stack", False):
        plan.print(
            "op_cl_rpc_url is set to '{}', changing to 'http://op-cl-1-op-node-op-geth{}:8547'".format(
                args["op_cl_rpc_url"], args["deployment_suffix"]
            )
        )
        args["op_cl_rpc_url"] = (
            "http://op-cl-1-op-node-op-geth" + args["deployment_suffix"] + ":8547"
        )
    # The optimism-package network_params is a frozen hash table, and is not modifiable during runtime.
    # The check will return fail() instead of dynamically changing the network_params name.
    if op_stack_args["optimism_package"]["chains"][0]["network_params"]["name"] != args[
        "deployment_suffix"
    ][1:] and deployment_stages.get("deploy_op_stack", False):
        fail(
            "op_stack_args network_params name is set to '{}', please change it to match deployment_suffix '{}'".format(
                op_stack_args["optimism_package"]["chains"][0]["network_params"][
                    "name"
                ],
                args["deployment_suffix"][1:],
            )
        )

    # Unsupported L1 engine check
    if args["l1_engine"] not in constants.L1_ENGINES:
        fail(
            "Unsupported L1 engine: '{}', please use one of {}".format(
                args["l1_engine"], constants.L1_ENGINES
            )
        )

    # Gas token enabled and gas token address check
    if (
        not args.get("gas_token_enabled", False)
        and args.get("gas_token_address", "0x0000000000000000000000000000000000000000")
        != "0x0000000000000000000000000000000000000000"
    ):
        fail(
            "Gas token address set to '{}' but gas token is not enabled".format(
                args.get("gas_token_address", "")
            )
        )

    # CDK Erigon normalcy and strict mode check
    if args["enable_normalcy"] and args["erigon_strict_mode"]:
        fail("normalcy and strict mode cannot be enabled together")

    # OP rollup deploy_optimistic_rollup and consensus_contract_type check
    if deployment_stages.get("deploy_optimism_rollup", False):
        user_consensus = user_args.get("args", {}).get("consensus_contract_type")
        if user_consensus and user_consensus != "pessimistic":
            plan.print(
                "consensus_contract_type was set to '{}', changing to pessimistic".format(
                    user_consensus
                )
            )
            args["consensus_contract_type"] = "pessimistic"

    # If OP-Succinct is enabled, OP-Rollup must be enabled
    if deployment_stages.get("deploy_op_succinct", False):
        if deployment_stages.get("deploy_optimism_rollup", False) == False:
            fail(
                "OP Succinct requires OP Rollup to be enabled. Change the deploy_optimism_rollup parameter"
            )
        if (
            args["agglayer_prover_sp1_key"] == None
            or args["agglayer_prover_sp1_key"] == ""
        ):
            fail(
                "OP Succinct requires a valid SPN key. Change the agglayer_prover_sp1_key"
            )

    # OP rollup check L1 blocktime >= L2 blocktime
    if deployment_stages.get("deploy_optimism_rollup", False):
        if (
            args.get("l1_seconds_per_slot", 12) < 2
        ):  # 2 seconds is the default blocktime for Optimism L2.
            fail(
                "OP Stack rollup requires L1 blocktime > 1 second. Change the l1_seconds_per_slot parameter"
            )
