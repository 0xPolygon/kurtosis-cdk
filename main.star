ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@2.0.0"
)
zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_permissionless_node_package = import_module("./zkevm_permissionless_node.star")


def run(plan, args):
    # Determine system architecture
    cpu_arch_result = plan.run_sh(run="uname -m | tr -d '\n'")
    cpu_arch = cpu_arch_result.output
    plan.print("Running on {} architecture".format(cpu_arch))
    if not "cpu_arch" in args:
        args["cpu_arch"] = cpu_arch

    args["is_cdk"] = False
    if args["zkevm_rollup_consensus"] == "PolygonValidiumEtrog":
        args["is_cdk"] = True

    # Deploy L1 chain
    # For now we'll stick with most of the defaults
    ethereum_package.run(
        plan,
        {
            "additional_services": [],
            "network_params": {
                # The ethereum package requires the network id to be a string.
                "network_id": str(args["l1_network_id"]),
                "preregistered_validator_keys_mnemonic": args[
                    "l1_preallocated_mnemonic"
                ],
            },
        },
    )

    # Create deploy parameters
    deploy_parameters_template = read_file(src="./templates/deploy_parameters.json")
    deploy_parameters_artifact = plan.render_templates(
        name="deploy-parameters-artifact",
        config={
            "deploy_parameters.json": struct(
                template=deploy_parameters_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "zkevm_deployment_salt": args["zkevm_deployment_salt"],
                    "zkevm_fork_id": args["zkevm_fork_id"],
                    "zkevm_l2_admin_address": args["zkevm_l2_admin_address"],
                    "zkevm_l2_admin_private_key": args["zkevm_l2_admin_private_key"],
                    "zkevm_l2_sequencer_address": args["zkevm_l2_sequencer_address"],
                    "zkevm_l2_aggregator_address": args["zkevm_l2_aggregator_address"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_test_deployment": args["zkevm_test_deployment"],
                },
            )
        },
    )
    # Create rollup paramaters
    create_rollup_parameters_template = read_file(
        src="./templates/create_rollup_parameters.json"
    )
    create_rollup_parameters_artifact = plan.render_templates(
        name="create-rollup-parameters-artifact",
        config={
            "create_rollup_parameters.json": struct(
                template=create_rollup_parameters_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "zkevm_l2_chain_id": args["zkevm_l2_chain_id"],
                    "zkevm_fork_id": args["zkevm_fork_id"],
                    "zkevm_rollup_consensus": args["zkevm_rollup_consensus"],
                    "zkevm_rollup_name": args["zkevm_rollup_name"],
                    "zkevm_rollup_description": args["zkevm_rollup_description"],
                    "zkevm_rollup_real_verifier": args["zkevm_rollup_real_verifier"],
                    "zkevm_da_protocol": args["zkevm_da_protocol"],
                    "zkevm_l2_admin_address": args["zkevm_l2_admin_address"],
                    "zkevm_l2_admin_private_key": args["zkevm_l2_admin_private_key"],
                    "zkevm_l2_aggregator_address": args["zkevm_l2_aggregator_address"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                },
            )
        },
    )
    # Create contract deployment script
    contract_deployment_script_template = read_file(
        src="./templates/run-contract-setup.sh"
    )
    contract_deployment_script_artifact = plan.render_templates(
        name="contract-deployment-script-artifact",
        config={
            "run-contract-setup.sh": struct(
                template=contract_deployment_script_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "cpu_arch": args["cpu_arch"],
                    "polycli_version": args["polycli_version"],
                    # l1
                    "l1_network_id": args["l1_network_id"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l1_preallocated_mnemonic": args["l1_preallocated_mnemonic"],
                    "l1_funding_amount": args["l1_funding_amount"],
                    # zkevm
                    "zkevm_fork_id": args["zkevm_fork_id"],
                    "zkevm_use_gas_token_contract": args[
                        "zkevm_use_gas_token_contract"
                    ],
                    "zkevm_dac_port": args["zkevm_dac_port"],
                    "zkevm_l2_admin_address": args["zkevm_l2_admin_address"],
                    "zkevm_l2_admin_private_key": args["zkevm_l2_admin_private_key"],
                    "zkevm_l2_sequencer_address": args["zkevm_l2_sequencer_address"],
                    "zkevm_l2_sequencer_private_key": args[
                        "zkevm_l2_sequencer_private_key"
                    ],
                    "zkevm_l2_aggregator_address": args["zkevm_l2_aggregator_address"],
                    "zkevm_l2_aggregator_private_key": args[
                        "zkevm_l2_aggregator_private_key"
                    ],
                    "zkevm_l2_agglayer_address": args["zkevm_l2_agglayer_address"],
                    "zkevm_l2_agglayer_private_key": args[
                        "zkevm_l2_agglayer_private_key"
                    ],
                    "zkevm_l2_dac_address": args["zkevm_l2_dac_address"],
                    "zkevm_l2_dac_private_key": args["zkevm_l2_dac_private_key"],
                    "zkevm_l2_claimtxmanager_private_key": args[
                        "zkevm_l2_claimtxmanager_private_key"
                    ],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                },
            )
        },
    )

    # Create bridge configuration
    bridge_config_template = read_file(src="./templates/bridge-config.toml")
    bridge_config_artifact = plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # bridge db
                    "zkevm_db_bridge_hostname": args["zkevm_db_bridge_hostname"],
                    "zkevm_db_bridge_name": args["zkevm_db_bridge_name"],
                    "zkevm_db_bridge_user": args["zkevm_db_bridge_user"],
                    "zkevm_db_bridge_password": args["zkevm_db_bridge_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_bridge_grpc_port": args["zkevm_bridge_grpc_port"],
                    "zkevm_bridge_rpc_port": args["zkevm_bridge_rpc_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                },
            )
        },
    )
    # Create AggLayer configuration
    agglayer_config_template = read_file(src="./templates/agglayer-config.toml")
    agglayer_config_artifact = plan.render_templates(
        name="agglayer-config-artifact",
        config={
            "agglayer-config.toml": struct(
                template=agglayer_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_network_id": args["l1_network_id"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # agglayer db
                    "zkevm_db_agglayer_hostname": args["zkevm_db_agglayer_hostname"],
                    "zkevm_db_agglayer_name": args["zkevm_db_agglayer_name"],
                    "zkevm_db_agglayer_user": args["zkevm_db_agglayer_user"],
                    "zkevm_db_agglayer_password": args["zkevm_db_agglayer_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_agglayer_port": args["zkevm_agglayer_port"],
                    "zkevm_prometheus_port": args["zkevm_prometheus_port"],
                },
            )
        },
    )
    # Create DAC configuration
    dac_config_template = read_file(src="./templates/dac-config.toml")
    dac_config_artifact = plan.render_templates(
        name="dac-config-artifact",
        config={
            "dac-config.toml": struct(
                template=dac_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l1_ws_url": args["l1_ws_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # dac db
                    "zkevm_db_dac_hostname": args["zkevm_db_dac_hostname"],
                    "zkevm_db_dac_name": args["zkevm_db_dac_name"],
                    "zkevm_db_dac_user": args["zkevm_db_dac_user"],
                    "zkevm_db_dac_password": args["zkevm_db_dac_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_dac_port": args["zkevm_dac_port"],
                },
            )
        },
    )
    # Create prover configuration
    prover_config_template = read_file(
        src="./templates/trusted-node/prover-config.json"
    )
    prover_config_artifact = plan.render_templates(
        name="prover-config-artifact",
        config={
            "prover-config.json": struct(
                template=prover_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    # prover db
                    "zkevm_db_prover_hostname": args["zkevm_db_prover_hostname"],
                    "zkevm_db_prover_name": args["zkevm_db_prover_name"],
                    "zkevm_db_prover_user": args["zkevm_db_prover_user"],
                    "zkevm_db_prover_password": args["zkevm_db_prover_password"],
                    # ports
                    "zkevm_aggregator_port": args["zkevm_aggregator_port"],
                    "zkevm_executor_port": args["zkevm_executor_port"],
                    "zkevm_hash_db_port": args["zkevm_hash_db_port"],
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                },
            )
        },
    )

    # Create helper service to deploy contracts
    zkevm_etc_directory = Directory(persistent_key="zkevm-artifacts")
    plan.add_service(
        name="contracts" + args["deployment_suffix"],
        config=ServiceConfig(
            image="node:20-bookworm",
            files={
                "/opt/zkevm": zkevm_etc_directory,
                "/opt/contract-deploy/": Directory(
                    artifact_names=[
                        deploy_parameters_artifact,
                        create_rollup_parameters_artifact,
                        contract_deployment_script_artifact,
                        prover_config_artifact,
                        bridge_config_artifact,
                        agglayer_config_artifact,
                        dac_config_artifact,
                    ]
                ),
            },
        ),
    )

    # TODO: Check if the contracts were already initialized.. I'm leaving this here for now, but it's not useful!!
    contract_init_stat = plan.exec(
        service_name="contracts" + args["deployment_suffix"],
        acceptable_codes=[0, 1],
        recipe=ExecRecipe(command=["stat", "/opt/zkevm/.init-complete.lock"]),
    )

    # Deploy contracts
    plan.exec(
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "git",
                "clone",
                "--depth",
                "1",
                "-b",
                args["zkevm_contracts_branch"],
                args["zkevm_contracts_repo"],
                "/opt/zkevm-contracts",
            ]
        ),
    )
    plan.exec(
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=["chmod", "a+x", "/opt/contract-deploy/run-contract-setup.sh"]
        ),
    )
    plan.print("Running zkEVM contract deployment. This might take some time...")
    plan.exec(
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(command=["/opt/contract-deploy/run-contract-setup.sh"]),
    )
    zkevm_configs = plan.store_service_files(
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm",
        name="zkevm",
        description="These are the files needed to start various node services",
    )
    genesis_artifact = plan.store_service_files(
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/genesis.json",
        name="genesis",
    )
    sequencer_keystore_artifact = plan.store_service_files(
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/sequencer.keystore",
        name="sequencer-keystore",
    )
    aggregator_keystore_artifact = plan.store_service_files(
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/aggregator.keystore",
        name="aggregator-keystore",
    )

    # Start databases
    event_db_init_script = plan.upload_files(
        src="./templates/databases/event-db-init.sql",
        name="event-db-init.sql" + args["deployment_suffix"],
    )
    prover_db_init_script = plan.upload_files(
        src="./templates/databases/prover-db-init.sql",
        name="prover-db-init.sql" + args["deployment_suffix"],
    )
    zkevm_databases_package.start_node_databases(
        plan, args, event_db_init_script, prover_db_init_script
    )
    zkevm_databases_package.start_peripheral_databases(plan, args)

    # Start prover
    zkevm_prover_package.start_prover(plan, args, prover_config_artifact)

    # Start AggLayer
    plan.add_service(
        name="zkevm-agglayer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_agglayer_image"],
            ports={
                "agglayer": PortSpec(
                    args["zkevm_agglayer_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            files={
                "/etc/": zkevm_configs,
            },
            entrypoint=[
                "/app/agglayer",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/agglayer-config.toml"],
        ),
    )

    # Start DAC
    plan.add_service(
        name="zkevm-dac" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_dac_image"],
            ports={
                "dac": PortSpec(args["zkevm_dac_port"], application_protocol="http"),
                # Does the DAC have prometheus?!
                # "prometheus": PortSpec(
                #     args["zkevm_prometheus_port"], application_protocol="http"
                # ),
            },
            files={
                "/etc/": zkevm_configs,
            },
            entrypoint=[
                "/app/cdk-data-availability",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/dac-config.toml"],
        ),
    )

    # Start the zkevm node components
    service_map = start_node_components(
        plan,
        args,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )

    # Start bridge
    zkevm_bridge_service = plan.add_service(
        name="zkevm-bridge-service" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_service_image"],
            ports={
                "bridge-rpc": PortSpec(
                    args["zkevm_bridge_rpc_port"], application_protocol="http"
                ),
                "bridge-grpc": PortSpec(
                    args["zkevm_bridge_grpc_port"], application_protocol="grpc"
                ),
            },
            files={
                "/etc/": zkevm_configs,
            },
            entrypoint=[
                "/app/zkevm-bridge",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
        ),
    )

    # Fetch addresses
    zkevm_bridge_address = extract_json_key_from_service(
        plan,
        "contracts" + args["deployment_suffix"],
        "/opt/zkevm/bridge-config.toml",
        "PolygonBridgeAddress",
    )  # "L2PolygonBridgeAddresses"
    rollup_manager_address = extract_json_key_from_service(
        plan,
        "contracts" + args["deployment_suffix"],
        "/opt/zkevm/bridge-config.toml",
        "PolygonRollupManagerAddress",
    )
    polygon_zkevm_address = extract_json_key_from_service(
        plan,
        "contracts" + args["deployment_suffix"],
        "/opt/zkevm/bridge-config.toml",
        "PolygonZkEVMAddress",
    )
    l1_eth_service = plan.get_service(name="el-1-geth-lighthouse")

    # Fetch port
    polygon_zkevm_rpc_http_port = service_map["rpc"].ports["http-rpc"]
    bridge_api_http_port = zkevm_bridge_service.ports["bridge-rpc"]

    # Start bridge-ui
    plan.add_service(
        name="zkevm-bridge-ui" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_ui_image"],
            ports={
                "bridge-ui": PortSpec(
                    args["zkevm_bridge_ui_port"], application_protocol="http"
                ),
            },
            env_vars={
                "ETHEREUM_RPC_URL": "http://{}:{}".format(
                    l1_eth_service.ip_address, l1_eth_service.ports["rpc"].number
                ),
                "POLYGON_ZK_EVM_RPC_URL": "http://{}:{}".format(
                    service_map["rpc"].ip_address, polygon_zkevm_rpc_http_port.number
                ),
                "BRIDGE_API_URL": "http://{}:{}".format(
                    zkevm_bridge_service.ip_address, bridge_api_http_port.number
                ),
                "ETHEREUM_BRIDGE_CONTRACT_ADDRESS": zkevm_bridge_address,
                "POLYGON_ZK_EVM_BRIDGE_CONTRACT_ADDRESS": zkevm_bridge_address,
                "ETHEREUM_FORCE_UPDATE_GLOBAL_EXIT_ROOT": "true",
                "ETHEREUM_PROOF_OF_EFFICIENCY_CONTRACT_ADDRESS": polygon_zkevm_address,
                "ETHEREUM_ROLLUP_MANAGER_ADDRESS": rollup_manager_address,
                "ETHEREUM_EXPLORER_URL": args["ethereum_explorer"],
                "POLYGON_ZK_EVM_EXPLORER_URL": args["polygon_zkevm_explorer"],
                "POLYGON_ZK_EVM_NETWORK_ID": "1",
                "ENABLE_FIAT_EXCHANGE_RATES": "false",
                "ENABLE_OUTDATED_NETWORK_MODAL": "false",
                "ENABLE_DEPOSIT_WARNING": "true",
                "ENABLE_REPORT_FORM": "false",
            },
            cmd=["run"],
        ),
    )

    # Start default permissionless node.
    # Note that an additional suffix will be added to the services.
    permissionless_args = args
    permissionless_args["deployment_suffix"] = "-pless" + args["deployment_suffix"]
    permissionless_args["genesis_artifact"] = genesis_artifact
    zkevm_permissionless_node_package.run(plan, args)


def start_node_components(
    plan,
    args,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
):
    # Create node configuration file.
    config_template = read_file(src="./templates/trusted-node/node-config.toml")
    config_artifact = plan.render_templates(
        config={
            "node-config.toml": struct(
                template=config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "is_cdk": args["is_cdk"],
                    "l1_network_id": args["l1_network_id"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    # zkevm
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "zkevm_l2_sequencer_address": args["zkevm_l2_sequencer_address"],
                    "zkevm_l2_aggregator_address": args["zkevm_l2_aggregator_address"],
                    "zkevm_l2_agglayer_address": args["zkevm_l2_agglayer_address"],
                    # state db
                    "zkevm_db_state_hostname": args["zkevm_db_state_hostname"],
                    "zkevm_db_state_name": args["zkevm_db_state_name"],
                    "zkevm_db_state_user": args["zkevm_db_state_user"],
                    "zkevm_db_state_password": args["zkevm_db_state_password"],
                    # pool db
                    "zkevm_db_pool_hostname": args["zkevm_db_pool_hostname"],
                    "zkevm_db_pool_name": args["zkevm_db_pool_name"],
                    "zkevm_db_pool_user": args["zkevm_db_pool_user"],
                    "zkevm_db_pool_password": args["zkevm_db_pool_password"],
                    # prover db
                    "zkevm_db_prover_hostname": args["zkevm_db_prover_hostname"],
                    "zkevm_db_prover_name": args["zkevm_db_prover_name"],
                    "zkevm_db_prover_user": args["zkevm_db_prover_user"],
                    "zkevm_db_prover_password": args["zkevm_db_prover_password"],
                    # event db
                    "zkevm_db_event_hostname": args["zkevm_db_event_hostname"],
                    "zkevm_db_event_name": args["zkevm_db_event_name"],
                    "zkevm_db_event_user": args["zkevm_db_event_user"],
                    "zkevm_db_event_password": args["zkevm_db_event_password"],
                    # ports
                    "zkevm_aggregator_port": args["zkevm_aggregator_port"],
                    "zkevm_data_streamer_port": args["zkevm_data_streamer_port"],
                    "zkevm_agglayer_port": args["zkevm_agglayer_port"],
                    "zkevm_hash_db_port": args["zkevm_hash_db_port"],
                    "zkevm_executor_port": args["zkevm_executor_port"],
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_rpc_ws_port": args["zkevm_rpc_ws_port"],
                    "zkevm_prometheus_port": args["zkevm_prometheus_port"],
                    "zkevm_pprof_port": args["zkevm_pprof_port"],
                },
            )
        },
        name="trusted-node-config",
    )

    service_map = {}
    # Deploy components.
    service_map["synchronizer"] = zkevm_node_package.start_synchronizer(
        plan, args, config_artifact, genesis_artifact
    )
    service_map["sequencer"] = zkevm_node_package.start_sequencer(
        plan, args, config_artifact, genesis_artifact
    )
    service_map["sequence_sender"] = zkevm_node_package.start_sequence_sender(
        plan, args, config_artifact, genesis_artifact, sequencer_keystore_artifact
    )
    service_map["start_aggregator"] = zkevm_node_package.start_aggregator(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )
    service_map["rpc"] = zkevm_node_package.start_rpc(
        plan, args, config_artifact, genesis_artifact
    )

    service_map["eth_tx_manager"] = zkevm_node_package.start_eth_tx_manager(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )

    service_map["l2_gas_pricer"] = zkevm_node_package.start_l2_gas_pricer(
        plan, args, config_artifact, genesis_artifact
    )
    return service_map


def extract_json_key_from_service(plan, service_name, filename, key):
    plan.print("Extracting contract addresses and ports...")
    exec_recipe = ExecRecipe(
        command=[
            "/bin/sh",
            "-c",
            "cat {} | grep -w '{}' | xargs -n1 | tail -1".format(filename, key),
        ]
    )
    result = plan.exec(service_name=service_name, recipe=exec_recipe)
    return result["output"]
