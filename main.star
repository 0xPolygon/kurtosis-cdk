ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@2.0.0"
)
service_package = import_module("./lib/service.star")
zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_permissionless_node_package = import_module("./zkevm_permissionless_node.star")


DEPLOYMENT_STAGE = struct(
    deploy_l1=1,
    configure_l1=2,
    deploy_central_environment=3,
    deploy_cdk_bridge_infra=4,
    deploy_permissionless_node=5,
)


def run(plan, args):
    plan.print("Deploying CDK environment for stages: " + str(args["stages"]))

    # Determine system architecture
    cpu_arch_result = plan.run_sh(
        run="uname -m | tr -d '\n'", description="Determining CPU system architecture"
    )
    cpu_arch = cpu_arch_result.output
    plan.print("Running on {} architecture".format(cpu_arch))
    if not "cpu_arch" in args:
        args["cpu_arch"] = cpu_arch

    args["is_cdk"] = False
    if args["zkevm_rollup_consensus"] == "PolygonValidiumEtrog":
        args["is_cdk"] = True

    ## STAGE 1: Deploy L1
    # For now we'll stick with most of the defaults
    if DEPLOYMENT_STAGE.deploy_l1 in args["stages"]:
        plan.print("Executing stage " + str(DEPLOYMENT_STAGE.deploy_l1))
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
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_l1))

    ## STAGE 2: Configure L1
    # Ffund accounts, deploy cdk contracts and create config files.
    if DEPLOYMENT_STAGE.configure_l1 in args["stages"]:
        plan.print("Executing stage " + str(DEPLOYMENT_STAGE.configure_l1))

        # Create deploy parameters
        deploy_parameters_template = read_file(src="./templates/deploy_parameters.json")
        deploy_parameters_artifact = plan.render_templates(
            name="deploy-parameters-artifact",
            config={
                "deploy_parameters.json": struct(
                    template=deploy_parameters_template, data=args
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
                    template=create_rollup_parameters_template, data=args
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
                    template=contract_deployment_script_template, data=args
                )
            },
        )

        # Create helper service to deploy contracts
        plan.add_service(
            name="contracts" + args["deployment_suffix"],
            config=ServiceConfig(
                image="node:20-bookworm",
                files={
                    "/opt/zkevm": Directory(persistent_key="zkevm-artifacts"),
                    "/opt/contract-deploy/": Directory(
                        artifact_names=[
                            deploy_parameters_artifact,
                            create_rollup_parameters_artifact,
                            contract_deployment_script_artifact,
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
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.configure_l1))

    # Get the genesis file.
    genesis_artifact = plan.store_service_files(
        name="genesis",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/genesis.json",
    )

    ## STAGE 3: Deploy trusted / central environment
    if DEPLOYMENT_STAGE.deploy_central_environment in args["stages"]:
        plan.print(
            "Executing stage " + str(DEPLOYMENT_STAGE.deploy_central_environment)
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
        prover_config_template = read_file(
            src="./templates/trusted-node/prover-config.json"
        )
        prover_config_artifact = plan.render_templates(
            config={
                "prover-config.json": struct(template=prover_config_template, data=args)
            },
            name="prover-config-artifact",
        )
        zkevm_prover_package.start_prover(plan, args, prover_config_artifact)

        # Start the zkevm node components
        sequencer_keystore_artifact = plan.store_service_files(
            name="sequencer-keystore",
            service_name="contracts" + args["deployment_suffix"],
            src="/opt/zkevm/sequencer.keystore",
        )
        aggregator_keystore_artifact = plan.store_service_files(
            name="aggregator-keystore",
            service_name="contracts" + args["deployment_suffix"],
            src="/opt/zkevm/aggregator.keystore",
        )
        start_node_components(
            plan,
            args,
            genesis_artifact,
            sequencer_keystore_artifact,
            aggregator_keystore_artifact,
        )
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_central_environment))

    ## STAGE 4: Deploy CDK/Bridge infra
    if DEPLOYMENT_STAGE.deploy_cdk_bridge_infra in args["stages"]:
        plan.print("Executing stage " + str(DEPLOYMENT_STAGE.deploy_cdk_bridge_infra))
        zkevm_bridge_service = start_bridge_service(plan, args)
        start_bridge_ui(plan, args, zkevm_bridge_service)
        start_agglayer(plan, args)
        start_dac(plan, args)
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_cdk_bridge_infra))

    ## STAGE 5: Deploy permissionless node
    if DEPLOYMENT_STAGE.deploy_permissionless_node in args["stages"]:
        plan.print(
            "Executing stage " + str(DEPLOYMENT_STAGE.deploy_permissionless_node)
        )

        # FIXME: This will create an alias of args and not a deep copy!
        permissionless_args = args
        # Note that an additional suffix will be added to the permissionless services.
        permissionless_args["deployment_suffix"] = "-pless" + args["deployment_suffix"]
        permissionless_args["genesis_artifact"] = genesis_artifact
        zkevm_permissionless_node_package.run(plan, args)
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_permissionless_node))


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
        config={"node-config.toml": struct(template=config_template, data=args)},
        name="trusted-node-config",
    )

    # Deploy components.
    service_map = {}
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


def start_bridge_service(plan, args):
    # Create bridge config.
    bridge_config_template = read_file(src="./templates/bridge-config.toml")
    rollup_manager_block_number = get_key_from_config(
        plan, args, "deploymentRollupManagerBlockNumber"
    )
    zkevm_global_exit_root_address = get_key_from_config(
        plan, args, "polygonZkEVMGlobalExitRootAddress"
    )
    zkevm_bridge_address = get_key_from_config(plan, args, "polygonZkEVMBridgeAddress")
    zkevm_rollup_manager_address = get_key_from_config(
        plan, args, "polygonRollupManagerAddress"
    )
    claimtx_keystore_artifact = plan.store_service_files(
        name="claimtxmanager-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/claimtxmanager.keystore",
    )
    zkevm_rollup_address = get_key_from_config(plan, args, "rollupAddress")
    bridge_config_artifact = plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # addresses
                    "rollup_manager_block_number": rollup_manager_block_number,
                    "zkevm_bridge_address": zkevm_bridge_address,
                    "zkevm_global_exit_root_address": zkevm_global_exit_root_address,
                    "zkevm_rollup_manager_address": zkevm_rollup_manager_address,
                    "zkevm_rollup_address": zkevm_rollup_address,
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

    # Start bridge service.
    return plan.add_service(
        name="zkevm-bridge-service" + args["deployment_suffix"],
        config=ServiceConfig(
            image="hermeznetwork/zkevm-bridge-service:v0.4.2",
            ports={
                "bridge-rpc": PortSpec(
                    args["zkevm_bridge_rpc_port"], application_protocol="http"
                ),
                "bridge-grpc": PortSpec(
                    args["zkevm_bridge_grpc_port"], application_protocol="grpc"
                ),
            },
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[bridge_config_artifact, claimtx_keystore_artifact]
                ),
            },
            entrypoint=[
                "/app/zkevm-bridge",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
        ),
    )


def start_bridge_ui(plan, args, bridge_service):
    l1_eth_service = plan.get_service(name="el-1-geth-lighthouse")
    zkevm_node_rpc = plan.get_service(name="zkevm-node-rpc" + args["deployment_suffix"])
    zkevm_bridge_address = get_key_from_config(
        plan, args, "polygonZkEVMGlobalExitRootAddress"
    )
    zkevm_rollup_manager_address = get_key_from_config(
        plan, args, "polygonRollupManagerAddress"
    )
    zkevm_rollup_address = get_key_from_config(plan, args, "rollupAddress")
    polygon_zkevm_rpc_http_port = zkevm_node_rpc.ports["http-rpc"]
    bridge_api_http_port = bridge_service.ports["bridge-rpc"]

    # Start bridge UI.
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
                    zkevm_node_rpc.ip_address,
                    polygon_zkevm_rpc_http_port.number,
                ),
                "BRIDGE_API_URL": "http://{}:{}".format(
                    bridge_service.ip_address, bridge_api_http_port.number
                ),
                "ETHEREUM_BRIDGE_CONTRACT_ADDRESS": zkevm_bridge_address,
                "POLYGON_ZK_EVM_BRIDGE_CONTRACT_ADDRESS": zkevm_bridge_address,
                "ETHEREUM_FORCE_UPDATE_GLOBAL_EXIT_ROOT": "true",
                "ETHEREUM_PROOF_OF_EFFICIENCY_CONTRACT_ADDRESS": zkevm_rollup_address,
                "ETHEREUM_ROLLUP_MANAGER_ADDRESS": zkevm_rollup_manager_address,
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


def start_agglayer(plan, args):
    # Create agglayer config.
    agglayer_config_template = read_file(src="./templates/agglayer-config.toml")
    rollup_manager_address = get_key_from_config(
        plan, args, "polygonRollupManagerAddress"
    )
    agglayer_keystore_artifact = plan.store_service_files(
        name="agglayer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/agglayer.keystore",
    )
    agglayer_config_artifact = plan.render_templates(
        name="agglayer-config-artifact",
        config={
            "agglayer-config.toml": struct(
                template=agglayer_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_network_id": args["l1_network_id"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # addresses
                    "rollup_manager_address": rollup_manager_address,
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

    # Start agglayer service.
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
                "/etc/zkevm": Directory(
                    artifact_names=[
                        agglayer_config_artifact,
                        agglayer_keystore_artifact,
                    ]
                ),
            },
            entrypoint=[
                "/app/agglayer",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/agglayer-config.toml"],
        ),
    )


def start_dac(plan, args):
    # Create DAC config.
    dac_config_template = read_file(src="./templates/dac-config.toml")
    rollup_address = get_key_from_config(plan, args, "rollupAddress")
    polygon_data_committee_address = get_key_from_config(
        plan, args, "polygonDataCommitteeAddress"
    )
    dac_keystore_artifact = plan.store_service_files(
        name="dac-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/dac.keystore",
    )

    dac_config_artifact = plan.render_templates(
        name="dac-config-artifact",
        config={
            "dac-config.toml": struct(
                template=dac_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l1_ws_url": args["l1_ws_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # addresses
                    "rollup_address": rollup_address,
                    "polygon_data_committee_address": polygon_data_committee_address,
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

    # Start DAC service.
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
                "/etc/zkevm": Directory(
                    artifact_names=[dac_config_artifact, dac_keystore_artifact]
                ),
            },
            entrypoint=[
                "/app/cdk-data-availability",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/dac-config.toml"],
        ),
    )


def get_key_from_config(plan, args, key):
    return service_package.extract_json_key_from_service(
        plan,
        "contracts" + args["deployment_suffix"],
        "/opt/zkevm/combined.json",
        key,
    )
