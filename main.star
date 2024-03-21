ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@2.0.0"
)
zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_permissionless_node_package = import_module("./zkevm_permissionless_node.star")

CONTRACTS_IMAGE = "node:20-bookworm"
CONTRACTS_BRANCH = "develop"

POSTGRES_IMAGE = "postgres:16.2"
POSTGRES_PORT_ID = "postgres"


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
        config={
            "deploy_parameters.json": struct(
                template=deploy_parameters_template, data=args
            )
        }
    )
    # Create rollup paramaters
    create_rollup_parameters_template = read_file(
        src="./templates/create_rollup_parameters.json"
    )
    create_rollup_parameters_artifact = plan.render_templates(
        config={
            "create_rollup_parameters.json": struct(
                template=create_rollup_parameters_template, data=args
            )
        }
    )
    # Create contract deployment script
    contract_deployment_script_template = read_file(
        src="./templates/run-contract-setup.sh"
    )
    contract_deployment_script_artifact = plan.render_templates(
        config={
            "run-contract-setup.sh": struct(
                template=contract_deployment_script_template, data=args
            )
        }
    )

    # Create bridge configuration
    bridge_config_template = read_file(src="./templates/bridge-config.toml")
    bridge_config_artifact = plan.render_templates(
        config={
            "bridge-config.toml": struct(template=bridge_config_template, data=args)
        }
    )
    # Create AggLayer configuration
    agglayer_config_template = read_file(src="./templates/agglayer-config.toml")
    agglayer_config_artifact = plan.render_templates(
        config={
            "agglayer-config.toml": struct(template=agglayer_config_template, data=args)
        }
    )
    # Create DAC configuration
    dac_config_template = read_file(src="./templates/dac-config.toml")
    dac_config_artifact = plan.render_templates(
        config={"dac-config.toml": struct(template=dac_config_template, data=args)}
    )
    # Create prover configuration
    prover_config_template = read_file(
        src="./templates/trusted-node/prover-config.json"
    )
    prover_config_artifact = plan.render_templates(
        config={
            "prover-config.json": struct(template=prover_config_template, data=args)
        }
    )

    # Create helper service to deploy contracts
    zkevm_etc_directory = Directory(persistent_key="zkevm-artifacts")
    plan.add_service(
        name="contracts" + args["deployment_suffix"],
        config=ServiceConfig(
            image=CONTRACTS_IMAGE,
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
    start_node_components(
        plan,
        args,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )

    # Start default permissionless node.
    # Note that an additional suffix will be added to the services.
    permissionless_args = args
    permissionless_args["deployment_suffix"] = "-pless" + args["deployment_suffix"]
    permissionless_args["genesis_artifact"] = genesis_artifact
    zkevm_permissionless_node_package.run(plan, args)

    # Start bridge
    plan.add_service(
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
                "/etc/": zkevm_configs,
            },
            entrypoint=[
                "/app/zkevm-bridge",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
        ),
    )


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
        config={"node-config.toml": struct(template=config_template, data=args)}
    )

    # Deploy components.

    zkevm_node_package.start_synchronizer(plan, args, config_artifact, genesis_artifact)
    zkevm_node_package.start_sequencer(plan, args, config_artifact, genesis_artifact)
    zkevm_node_package.start_sequence_sender(
        plan, args, config_artifact, genesis_artifact, sequencer_keystore_artifact
    )
    zkevm_node_package.start_aggregator(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )
    zkevm_node_package.start_rpc(plan, args, config_artifact, genesis_artifact)

    zkevm_node_package.start_eth_tx_manager(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )

    zkevm_node_package.start_l2_gas_pricer(
        plan, args, config_artifact, genesis_artifact
    )
