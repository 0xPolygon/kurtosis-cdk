ethereum_package = import_module(
    "github.com/kurtosis-tech/ethereum-package/main.star@2.0.0"
)

CONTRACTS_IMAGE = "node:20-bookworm"
CONTRACTS_BRANCH = "develop"

POSTGRES_IMAGE = "postgres:16.2"
POSTGRES_PORT_ID = "postgres"


def run(plan, args):
    deployment_label = args["deployment_idx"]

    # Determine system architecture.
    cpu_arch_result = plan.run_sh(run="uname -m | tr -d '\n'")
    cpu_arch = cpu_arch_result.output
    plan.print("Running on {} architecture".format(cpu_arch))
    if not "cpu_arch" in args:
        args["cpu_arch"] = cpu_arch

    args["is_cdk"] = False
    if args["zkevm_rollup_consensus"] == "PolygonValidiumEtrog":
        args["is_cdk"] = True

    # Make ethereum package availabile. For now we'll stick with most
    # of the defaults
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

    # Deploy Parameters
    deploy_parameters_template = read_file(src="./templates/deploy_parameters.json")
    deploy_parameters_artifact = plan.render_templates(
        config={
            "deploy_parameters.json": struct(
                template=deploy_parameters_template, data=args
            )
        }
    )
    # Create Rollup Paramaters
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
    # Contract Deployment script
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
    # Node configuration
    node_config_template = read_file(src="./templates/node-config.toml")
    node_config_artifact = plan.render_templates(
        config={"node-config.toml": struct(template=node_config_template, data=args)}
    )
    # Bridge configuration
    bridge_config_template = read_file(src="./templates/bridge-config.toml")
    bridge_config_artifact = plan.render_templates(
        config={
            "bridge-config.toml": struct(template=bridge_config_template, data=args)
        }
    )

    # agglayer configuration
    agglayer_config_template = read_file(src="./templates/agglayer-config.toml")
    agglayer_config_artifact = plan.render_templates(
        config={
            "agglayer-config.toml": struct(template=agglayer_config_template, data=args)
        }
    )

    # Prover configuration
    prover_config_template = read_file(src="./templates/prover-config.json")
    prover_config_artifact = plan.render_templates(
        config={
            "prover-config.json": struct(template=prover_config_template, data=args)
        }
    )

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
                        node_config_artifact,
                        prover_config_artifact,
                        bridge_config_artifact,
                        agglayer_config_artifact,
                    ]
                ),
            },
        ),
    )

    plan.add_service(
        name="netshoot-debug",
        config=ServiceConfig(
            image="nicolaka/netshoot",
        ),
    )

    # check if the contracts were already initialized.. I'm leaving
    # this here for now, but it's not useful
    contract_init_stat = plan.exec(
        service_name="contracts" + args["deployment_idx"],
        acceptable_codes=[0, 1],
        recipe=ExecRecipe(command=["stat", "/opt/zkevm/.init-complete.lock"]),
    )

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

    # plan.stop_service(
    #     name = "contracts"+args["deployment_idx"]
    # )

    add_databases(plan, args)

    plan.add_service(
        name="zkevm-prover" + args["deployment_idx"],
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

    plan.add_service(
        name="zkevm-node-synchronizer" + args["deployment_idx"],
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
                "/etc/zkevm/node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "synchronizer",
            ],
        ),
    )

    plan.add_service(
        name="zkevm-node-sequencer" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            files={
                "/etc/": zkevm_configs,
            },
            ports={
                "trusted-rpc": PortSpec(
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
                "/etc/zkevm/node-config.toml",
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
        name="zkevm-node-sequencersender" + args["deployment_idx"],
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
                "/etc/zkevm/node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "sequencersender",
            ],
        ),
    )

    plan.add_service(
        name="zkevm-node-aggregator" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            ports={
                "trusted-aggregator": PortSpec(
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
                "/etc/zkevm/node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "aggregator",
            ],
        ),
    )

    plan.add_service(
        name="zkevm-node-rpc" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            ports={
                "trusted-rpc": PortSpec(
                    args["zkevm_rpc_http_port"], application_protocol="http"
                ),
                "trusted-ws": PortSpec(
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
                "--cfg",
                "/etc/zkevm/node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "rpc",
                "--http.api",
                "eth,net,debug,zkevm,txpool,web3",
            ],
        ),
    )

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
                "/etc/zkevm/node-config.toml",
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
                "/etc/zkevm/node-config.toml",
                "--network",
                "custom",
                "--custom-network-file",
                "/etc/zkevm/genesis.json",
                "--components",
                "l2gaspricer",
            ],
        ),
    )

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


def add_databases(plan, args):
    prover_db_init_artifact = plan.upload_files(
        src="./templates/prover-db-init.sql", name="prover-db-init.sql"
    )

    prover_db = plan.add_service(
        name=args["zkevm_db_prover_hostname"] + args["deployment_idx"],
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                POSTGRES_PORT_ID: PortSpec(
                    args["zkevm_db_postgres_port"], application_protocol="postgresql"
                ),
            },
            env_vars={
                "POSTGRES_DB": args["zkevm_db_prover_name"],
                "POSTGRES_USER": args["zkevm_db_prover_user"],
                "POSTGRES_PASSWORD": args["zkevm_db_prover_password"],
            },
            files={
                "/docker-entrypoint-initdb.d/": prover_db_init_artifact,
            },
        ),
    )
    pool_db = plan.add_service(
        name=args["zkevm_db_pool_hostname"] + args["deployment_idx"],
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                POSTGRES_PORT_ID: PortSpec(
                    args["zkevm_db_postgres_port"], application_protocol="postgresql"
                ),
            },
            env_vars={
                "POSTGRES_DB": args["zkevm_db_pool_name"],
                "POSTGRES_USER": args["zkevm_db_pool_user"],
                "POSTGRES_PASSWORD": args["zkevm_db_pool_password"],
            },
        ),
    )

    event_db_init_artifact = plan.upload_files(
        src="./templates/event-db-init.sql", name="event-db-init.sql"
    )

    event_db = plan.add_service(
        name=args["zkevm_db_event_hostname"] + args["deployment_idx"],
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                POSTGRES_PORT_ID: PortSpec(
                    args["zkevm_db_postgres_port"], application_protocol="postgresql"
                ),
            },
            env_vars={
                "POSTGRES_DB": args["zkevm_db_event_name"],
                "POSTGRES_USER": args["zkevm_db_event_user"],
                "POSTGRES_PASSWORD": args["zkevm_db_event_password"],
            },
            files={
                "/docker-entrypoint-initdb.d/": event_db_init_artifact,
            },
        ),
    )

    state_db = plan.add_service(
        name=args["zkevm_db_state_hostname"] + args["deployment_idx"],
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                POSTGRES_PORT_ID: PortSpec(
                    args["zkevm_db_postgres_port"], application_protocol="postgresql"
                ),
            },
            env_vars={
                "POSTGRES_DB": args["zkevm_db_state_name"],
                "POSTGRES_USER": args["zkevm_db_state_user"],
                "POSTGRES_PASSWORD": args["zkevm_db_state_password"],
            },
        ),
    )
    bridge_db = plan.add_service(
        name=args["zkevm_db_bridge_hostname"] + args["deployment_idx"],
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                POSTGRES_PORT_ID: PortSpec(
                    args["zkevm_db_postgres_port"], application_protocol="postgresql"
                ),
            },
            env_vars={
                "POSTGRES_DB": args["zkevm_db_bridge_name"],
                "POSTGRES_USER": args["zkevm_db_bridge_user"],
                "POSTGRES_PASSWORD": args["zkevm_db_bridge_password"],
            },
        ),
    )
    agglayer_db = plan.add_service(
        name=args["zkevm_db_agglayer_hostname"] + args["deployment_idx"],
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                POSTGRES_PORT_ID: PortSpec(
                    args["zkevm_db_postgres_port"], application_protocol="postgresql"
                ),
            },
            env_vars={
                "POSTGRES_DB": args["zkevm_db_agglayer_name"],
                "POSTGRES_USER": args["zkevm_db_agglayer_user"],
                "POSTGRES_PASSWORD": args["zkevm_db_agglayer_password"],
            },
        ),
    )

