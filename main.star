ethereum_package = import_module("./ethereum.star")
deploy_zkevm_contracts_package = import_module("./deploy_zkevm_contracts.star")
cdk_databases_package = import_module("./cdk_databases.star")
cdk_central_environment_package = import_module("./cdk_central_environment.star")
cdk_bridge_infra_package = import_module("./cdk_bridge_infra.star")
zkevm_permissionless_node_package = import_module("./zkevm_permissionless_node.star")
observability_package = import_module("./observability.star")
workload_package = import_module("./workload.star")
blutgang_package = import_module("./cdk_blutgang.star")


def run(
    plan,
    deploy_l1=True,
    deploy_zkevm_contracts_on_l1=True,
    deploy_databases=True,
    deploy_cdk_bridge_infra=True,
    deploy_cdk_central_environment=True,
    deploy_zkevm_permissionless_node=True,
    deploy_observability=True,
    deploy_blutgang=True,
    apply_workload=False,
    args={
        "deployment_suffix": "-001",
        "zkevm_prover_image": "hermeznetwork/zkevm-prover:v6.0.0",
        "zkevm_node_image": "0xpolygon/cdk-validium-node:0.6.5-cdk",
        "zkevm_da_image": "0xpolygon/cdk-data-availability:0.0.7",
        "zkevm_contracts_image": "leovct/zkevm-contracts",
        "zkevm_agglayer_image": "0xpolygon/agglayer:0.1.3",
        "zkevm_bridge_service_image": "hermeznetwork/zkevm-bridge-service:v0.4.2",
        "panoptichain_image": "minhdvu/panoptichain",
        "zkevm_bridge_ui_image": "leovct/zkevm-bridge-ui:multi-network",
        "zkevm_bridge_proxy_image": "haproxy:2.9.7",
        "workload_image": "leovct/workload:0.0.1",
        "zkevm_hash_db_port": 50061,
        "zkevm_executor_port": 50071,
        "zkevm_aggregator_port": 50081,
        "zkevm_pprof_port": 6060,
        "zkevm_prometheus_port": 9091,
        "zkevm_data_streamer_port": 6900,
        "zkevm_rpc_http_port": 8123,
        "zkevm_rpc_ws_port": 8133,
        "zkevm_bridge_rpc_port": 8080,
        "zkevm_bridge_grpc_port": 9090,
        "zkevm_bridge_ui_port": 80,
        "zkevm_agglayer_port": 4444,
        "zkevm_dac_port": 8484,
        "zkevm_l2_sequencer_address": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
        "zkevm_l2_sequencer_private_key": "0x183c492d0ba156041a7f31a1b188958a7a22eebadca741a7fe64436092dc3181",
        "zkevm_l2_aggregator_address": "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
        "zkevm_l2_aggregator_private_key": "0x2857ca0e7748448f3a50469f7ffe55cde7299d5696aedd72cfe18a06fb856970",
        "zkevm_l2_claimtxmanager_address": "0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8",
        "zkevm_l2_claimtxmanager_private_key": "0x8d5c9ecd4ba2a195db3777c8412f8e3370ae9adffac222a54a84e116c7f8b934",
        "zkevm_l2_timelock_address": "0x130aA39Aa80407BD251c3d274d161ca302c52B7A",
        "zkevm_l2_timelock_private_key": "0x80051baf5a0a749296b9dcdb4a38a264d2eea6d43edcf012d20b5560708cf45f",
        "zkevm_l2_admin_address": "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
        "zkevm_l2_admin_private_key": "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625",
        "zkevm_l2_loadtest_address": "0x81457240ff5b49CaF176885ED07e3E7BFbE9Fb81",
        "zkevm_l2_loadtest_private_key": "0xd7df6d64c569ffdfe7c56e6b34e7a2bdc7b7583db74512a9ffe26fe07faaa5de",
        "zkevm_l2_agglayer_address": "0x351e560852ee001d5D19b5912a269F849f59479a",
        "zkevm_l2_agglayer_private_key": "0x1d45f90c0a9814d8b8af968fa0677dab2a8ff0266f33b136e560fe420858a419",
        "zkevm_l2_dac_address": "0x5951F5b2604c9B42E478d5e2B2437F44073eF9A6",
        "zkevm_l2_dac_private_key": "0x85d836ee6ea6f48bae27b31535e6fc2eefe056f2276b9353aafb294277d8159b",
        "zkevm_l2_proofsigner_address": "0x7569cc70950726784c8D3bB256F48e43259Cb445",
        "zkevm_l2_proofsigner_private_key": "0x77254a70a02223acebf84b6ed8afddff9d3203e31ad219b2bf900f4780cf9b51",
        "zkevm_l2_keystore_password": "pSnv6Dh5s9ahuzGzH9RoCDrKAMddaX3m",
        "zkevm_db_postgres_port": 5432,
        "zkevm_db_agglayer_hostname": "agglayer-db",
        "zkevm_db_agglayer_name": "agglayer_db",
        "zkevm_db_agglayer_user": "agglayer_user",
        "zkevm_db_agglayer_password": "PzycR2uB6PQv8ahj465ExvdyRLkknRNW",
        "zkevm_db_bridge_hostname": "bridge-db",
        "zkevm_db_bridge_name": "bridge_db",
        "zkevm_db_bridge_user": "bridge_user",
        "zkevm_db_bridge_password": "aXPqaRvgo5DfnTbHtpYS9rMhVpjvb6tY",
        "zkevm_db_dac_hostname": "dac-db",
        "zkevm_db_dac_name": "dac_db",
        "zkevm_db_dac_user": "dac_user",
        "zkevm_db_dac_password": "PzycR2uB6PQv8ahj465ExvdyRLkknRNW",
        "zkevm_db_event_hostname": "event-db",
        "zkevm_db_event_name": "event_db",
        "zkevm_db_event_user": "event_user",
        "zkevm_db_event_password": "rJXJN6iUAczh4oz8HRKYbVM8yC7tPeZm",
        "zkevm_db_pool_hostname": "pool-db",
        "zkevm_db_pool_name": "pool_db",
        "zkevm_db_pool_user": "pool_user",
        "zkevm_db_pool_password": "Qso5wMcLAN3oF7EfaawzgWKUUKWM3Vov",
        "zkevm_db_prover_hostname": "prover-db",
        "zkevm_db_prover_name": "prover_db",
        "zkevm_db_prover_user": "prover_user",
        "zkevm_db_prover_password": "SR5xq2KZPgvQkPDranCRhvkv6pnqfo77",
        "zkevm_db_state_hostname": "state-db",
        "zkevm_db_state_name": "state_db",
        "zkevm_db_state_user": "state_user",
        "zkevm_db_state_password": "rHTX7EpajF8zYDPatN32rH3B2pn89dmq",
        "l1_chain_id": 271828,
        "l1_preallocated_mnemonic": "code code code code code code code code code code code quality",
        "l1_funding_amount": "100ether",
        "l1_rpc_url": "http://el-1-geth-lighthouse:8545",
        "l1_ws_url": "ws://el-1-geth-lighthouse:8546",
        "l1_additional_services": [],
        "zkevm_rollup_chain_id": 10101,
        "zkevm_rollup_fork_id": 9,
        "zkevm_rollup_consensus": "PolygonValidiumEtrog",
        "polygon_zkevm_explorer": "https://explorer.private/",
        "l1_explorer_url": "https://sepolia.etherscan.io/",
        "zkevm_use_gas_token_contract": False,
        "trusted_sequencer_node_uri": "zkevm-node-sequencer-001:6900",
        "zkevm_aggregator_host": "zkevm-node-aggregator-001",
        "genesis_file": "templates/permissionless-node/genesis.json",
        "polycli_version": "v0.1.42",
        "workload_commands": [
            "polycli_loadtest_on_l2.sh t",  # eth transfers
            "polycli_loadtest_on_l2.sh 2",  # erc20 transfers
            "polycli_loadtest_on_l2.sh 7",  # erc721 mints
            "polycli_loadtest_on_l2.sh v3",  # uniswapv3 swaps
            "polycli_rpcfuzz_on_l2.sh",  # rpc calls
        ],
        "blutgang_image": "makemake1337/blutgang:0.3.5",
        "blutgang_rpc_port": 55555,
        "blutgang_admin_port": 55556,
    },
):
    """Deploy a Polygon CDK Devnet with various configurable options.

    Args:
        deploy_l1 (bool): Deploy local l1.
        deploy_zkevm_contracts_on_l1(bool): Deploy zkevm contracts on L1 (and also fund accounts).
        deploy_databases(bool): Deploy zkevm node and cdk peripheral databases.
        deploy_cdk_central_environment(bool): Deploy cdk central/trusted environment.
        deploy_cdk_bridge_infra(bool): Deploy cdk/bridge infrastructure.
        deploy_zkevm_permissionless_node(bool): Deploy permissionless node.
        deploy_observability(bool): Deploys observability stack.
        args(json): Configures other aspects of the environment.
    Returns:
        A full deployment of Polygon CDK.
    """
    plan.print("Deploying CDK environment...")

    # Deploy a local L1.
    if deploy_l1:
        plan.print("Deploying a local L1")
        ethereum_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of a local L1")

    # Deploy zkevm contracts on L1.
    if deploy_zkevm_contracts_on_l1:
        plan.print("Deploying zkevm contracts on L1")
        deploy_zkevm_contracts_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of zkevm contracts on L1")

    # Deploy zkevm node and cdk peripheral databases.
    if deploy_databases:
        plan.print("Deploying zkevm node and cdk peripheral databases")
        cdk_databases_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of zkevm node and cdk peripheral databases")

    # Get the genesis file.
    genesis_artifact = ""
    if deploy_cdk_central_environment or deploy_zkevm_permissionless_node:
        plan.print("Getting genesis file...")
        genesis_artifact = plan.store_service_files(
            name="genesis",
            service_name="contracts" + args["deployment_suffix"],
            src="/opt/zkevm/genesis.json",
        )

    # Deploy cdk central/trusted environment.
    if deploy_cdk_central_environment:
        plan.print("Deploying cdk central/trusted environment")
        central_environment_args = dict(args)
        central_environment_args["genesis_artifact"] = genesis_artifact
        cdk_central_environment_package.run(plan, central_environment_args)
    else:
        plan.print("Skipping the deployment of cdk central/trusted environment")

    # Deploy cdk/bridge infrastructure.
    if deploy_cdk_bridge_infra:
        plan.print("Deploying cdk/bridge infrastructure")
        cdk_bridge_infra_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of cdk/bridge infrastructure")

    # Deploy permissionless node
    if deploy_zkevm_permissionless_node:
        plan.print("Deploying zkevm permissionless node")
        # Note that an additional suffix will be added to the permissionless services.
        permissionless_node_args = dict(args)
        permissionless_node_args["deployment_suffix"] = (
            "-pless" + args["deployment_suffix"]
        )
        permissionless_node_args["genesis_artifact"] = genesis_artifact
        zkevm_permissionless_node_package.run(plan, permissionless_node_args)
    else:
        plan.print("Skipping the deployment of zkevm permissionless node")

    # Deploy observability stack
    if deploy_observability:
        plan.print("Deploying the observability stack")
        observability_args = dict(args)
        observability_package.run(plan, observability_args)
    else:
        plan.print("Skipping the deployment of the observability stack")

    # Apply workload
    if apply_workload:
        plan.print("Apply workload")
        workload_package.run(plan, args)
    else:
        plan.print("Skipping workload application")

    # Deploy blutgang for caching
    if deploy_blutgang:
        plan.print("Deploying blutgang")
        blutgang_args = dict(args)
        blutgang_package.run(plan, blutgang_args)
    else:
        plan.print("Skipping the deployment of blutgang")
