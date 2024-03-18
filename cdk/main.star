ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@2.0.0"
)

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
                "network_id": args["l1_network_id"],
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

    # Create trusted node configuration
    trusted_node_config_template = read_file(src="./templates/trusted-node-config.toml")
    trusted_node_config_artifact = plan.render_templates(
        config={
            "trusted-node-config.toml": struct(
                template=trusted_node_config_template, data=args
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
    prover_config_template = read_file(src="./templates/prover-config.json")
    prover_config_artifact = plan.render_templates(
        config={
            "prover-config.json": struct(template=prover_config_template, data=args)
        }
    )

    # Create helper service to deploy contracts
    zkevm_etc_directory = Directory(persistent_key="zkevm-artifacts")
    plan.add_service(
        name="contracts" + args["deployment_idx"],
        config=ServiceConfig(
            image=CONTRACTS_IMAGE,
            files={
                "/opt/zkevm": zkevm_etc_directory,
                "/opt/contract-deploy/": Directory(
                    artifact_names=[
                        deploy_parameters_artifact,
                        create_rollup_parameters_artifact,
                        contract_deployment_script_artifact,
                        trusted_node_config_artifact,
                        prover_config_artifact,
                        bridge_config_artifact,
                        agglayer_config_artifact,
                        dac_config_artifact,
                    ]
                ),
            },
        ),
    )

    # Debug service
    plan.add_service(
        name="netshoot-debug",
        config=ServiceConfig(
            image="nicolaka/netshoot",
        ),
    )

    # TODO: Check if the contracts were already initialized.. I'm leaving this here for now, but it's not useful!!
    contract_init_stat = plan.exec(
        service_name="contracts" + args["deployment_idx"],
        acceptable_codes=[0, 1],
        recipe=ExecRecipe(command=["stat", "/opt/zkevm/.init-complete.lock"]),
    )

    # Deploy contracts
    plan.exec(
        service_name="contracts" + args["deployment_idx"],
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
        service_name="contracts" + args["deployment_idx"],
        recipe=ExecRecipe(
            command=["chmod", "a+x", "/opt/contract-deploy/run-contract-setup.sh"]
        ),
    )
    plan.print("Running zkEVM contract deployment. This might take some time...")
    plan.exec(
        service_name="contracts" + args["deployment_idx"],
        recipe=ExecRecipe(command=["/opt/contract-deploy/run-contract-setup.sh"]),
    )
    zkevm_configs = plan.store_service_files(
        service_name="contracts" + args["deployment_idx"],
        src="/opt/zkevm",
        name="zkevm",
        description="These are the files needed to start various node services",
    )

    # Start databases
    prover_db_init_script = plan.upload_files(
        src="./templates/prover-db-init.sql", name="prover-db-init.sql"
    )
    event_db_init_script = plan.upload_files(
        src="./templates/event-db-init.sql", name="event-db-init.sql"
    )
    start_trusted_node_databases(
        plan, args, prover_db_init_script, event_db_init_script
    )

    # Start prover
    plan.add_service(
        name="zkevm-trusted-prover" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_prover_image"],
            ports={
                "hash-db-server": PortSpec(
                    args["zkevm_hash_db_port"], application_protocol="grpc"
                ),
                "executor-server": PortSpec(
                    args["zkevm_executor_port"], application_protocol="grpc"
                ),
            },
            files={
                "/etc/": zkevm_configs,
            },
            entrypoint=["/bin/bash", "-c"],
            cmd=[
                '[[ "{0}" == "aarch64" || "{0}" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; \
                /usr/local/bin/zkProver -c /etc/zkevm/prover-config.json'.format(
                    cpu_arch
                ),
            ],
        ),
    )

    # Start AggLayer
    start_postgres_db(
        plan,
        name=args["zkevm_db_agglayer_hostname"] + args["deployment_idx"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_agglayer_name"],
        user=args["zkevm_db_agglayer_user"],
        password=args["zkevm_db_agglayer_password"],
    )
    plan.add_service(
        name="zkevm-agglayer" + args["deployment_idx"],
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
    start_postgres_db(
        plan,
        name=args["zkevm_db_dac_hostname"] + args["deployment_idx"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_dac_name"],
        user=args["zkevm_db_dac_user"],
        password=args["zkevm_db_dac_password"],
    )
    plan.add_service(
        name="zkevm-dac" + args["deployment_idx"],
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

    # Start synchronizer
    plan.add_service(
        name="zkevm-node-trusted-synchronizer" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            files={
                "/etc/": zkevm_configs,
            },
            ports={
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg",
                "/etc/zkevm/trusted-node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "synchronizer",
            ],
        ),
    )

    # Start sequencer
    plan.add_service(
        name="zkevm-node-trusted-sequencer" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            files={
                "/etc/": zkevm_configs,
            },
            ports={
                "rpc": PortSpec(
                    args["zkevm_rpc_http_port"], application_protocol="http"
                ),
                "data-streamer": PortSpec(
                    args["zkevm_data_streamer_port"], application_protocol="datastream"
                ),
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg",
                "/etc/zkevm/trusted-node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "sequencer,rpc",
                "--http.api",
                "eth,net,debug,zkevm,txpool,web3",
            ],
        ),
    )
    plan.add_service(
        name="zkevm-node-trusted-sequencesender" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            files={
                "/etc/": zkevm_configs,
            },
            ports={
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg",
                "/etc/zkevm/trusted-node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "sequence-sender",
            ],
        ),
    )

    # Start aggregator
    plan.add_service(
        name="zkevm-node-trusted-aggregator" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            ports={
                "aggregator": PortSpec(
                    args["zkevm_aggregator_port"], application_protocol="grpc"
                ),
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            files={
                "/etc/": zkevm_configs,
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg",
                "/etc/zkevm/trusted-node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "aggregator",
            ],
        ),
    )

    # Start trusted RPC
    plan.add_service(
        name="zkevm-node-trusted-rpc" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            ports={
                "http-rpc": PortSpec(
                    args["zkevm_rpc_http_port"], application_protocol="http"
                ),
                "ws-rpc": PortSpec(
                    args["zkevm_rpc_ws_port"], application_protocol="ws"
                ),
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            files={
                "/etc/": zkevm_configs,
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg=/etc/zkevm/trusted-node-config.toml",
                "--network=custom",
                "--custom-network-file=/etc/zkevm/genesis.json",
                "--components=rpc",
                "--http.api=eth,net,debug,zkevm,txpool,web3",
            ],
        ),
    )

    # Start eth-tx-manager and l2-gas-pricer
    plan.add_service(
        name="zkevm-node-eth-tx-manager" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            files={
                "/etc/": zkevm_configs,
            },
            ports={
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg",
                "/etc/zkevm/trusted-node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "eth-tx-manager",
            ],
        ),
    )
    plan.add_service(
        name="zkevm-node-l2-gas-pricer" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            files={
                "/etc/": zkevm_configs,
            },
            ports={
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg",
                "/etc/zkevm/trusted-node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "l2gaspricer",
            ],
        ),
    )

    # Start bridge
    plan.add_service(
        name="zkevm-bridge-service" + args["deployment_idx"],
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


def start_trusted_node_databases(
    plan, args, prover_db_init_script, event_db_init_script
):
    postgres_port = args["zkevm_db_postgres_port"]

    # Start prover db
    start_postgres_db(
        plan,
        name="trusted-" + args["zkevm_db_prover_hostname"] + args["deployment_idx"],
        port=postgres_port,
        db=args["zkevm_db_prover_name"],
        user=args["zkevm_db_prover_user"],
        password=args["zkevm_db_prover_password"],
        init_script_artifact_name=prover_db_init_script,
    )

    # Start pool db
    start_postgres_db(
        plan,
        name="trusted-" + args["zkevm_db_pool_hostname"] + args["deployment_idx"],
        port=postgres_port,
        db=args["zkevm_db_pool_name"],
        user=args["zkevm_db_pool_user"],
        password=args["zkevm_db_pool_password"],
    )

    # Start event db
    start_postgres_db(
        plan,
        name="trusted-" + args["zkevm_db_event_hostname"] + args["deployment_idx"],
        port=postgres_port,
        db=args["zkevm_db_event_name"],
        user=args["zkevm_db_event_user"],
        password=args["zkevm_db_event_password"],
        init_script_artifact_name=event_db_init_script,
    )

    # Start state db
    start_postgres_db(
        plan,
        name="trusted-" + args["zkevm_db_state_hostname"] + args["deployment_idx"],
        port=postgres_port,
        db=args["zkevm_db_state_name"],
        user=args["zkevm_db_state_user"],
        password=args["zkevm_db_state_password"],
    )

    # Start bridge db
    start_postgres_db(
        plan,
        name=args["zkevm_db_bridge_hostname"] + args["deployment_idx"],
        port=postgres_port,
        db=args["zkevm_db_bridge_name"],
        user=args["zkevm_db_bridge_user"],
        password=args["zkevm_db_bridge_password"],
    )


def start_postgres_db(
    plan, name, port, db, user, password, init_script_artifact_name=""
):
    files = {}
    if init_script_artifact_name != "":
        files["/docker-entrypoint-initdb.d/"] = init_script_artifact_name
    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                POSTGRES_PORT_ID: PortSpec(port, application_protocol="postgresql"),
            },
            env_vars={
                "POSTGRES_DB": db,
                "POSTGRES_USER": user,
                "POSTGRES_PASSWORD": password,
            },
            files=files,
        ),
    )
