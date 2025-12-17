zkevm_prover = import_module("./zkevm_prover.star")


CDK_ERIGON_TYPE = struct(
    sequencer="sequencer",
    rpc="rpc",
)


# Port identifiers and numbers.
HTTP_RPC_PORT_ID = "http"
HTTP_RPC_PORT_NUMBER = 8123

WS_RPC_PORT_ID = "ws"
WS_RPC_PORT_NUMBER = 8133

DATA_STREAMER_PORT_ID = "data-streamer"
DATA_STREAMER_PORT_NUMBER = 6900

PPROF_PORT_ID = "pprof"
PPPROF_PORT_NUMBER = 6060

METRICS_PORT_ID = "prometheus"
METRICS_PORT_NUMBER = 9091


def run_sequencer(plan, args, contract_setup_addresses):
    config_artifact = plan.render_templates(
        name="cdk-erigon-sequencer-config-artifact",
        config={
            "config.yaml": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/cdk-erigon/config.yml"
                ),
                data={
                    "zkevm_data_stream_port": args["zkevm_data_streamer_port"],
                    "is_sequencer": True,
                    "consensus_contract_type": args["consensus_contract_type"],
                    "l1_sync_start_block": 1 if args["anvil_state_file"] else 0,
                    "prometheus_port": args["prometheus_port"],
                    "zkevm_executor_port_number": zkevm_prover.EXECUTOR_PORT_NUMBER,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    _run(plan, args, CDK_ERIGON_TYPE.sequencer, config_artifact)


def run_rpc(plan, args, contract_setup_addresses):
    zkevm_sequencer_service = plan.get_service(
        name=args["sequencer_name"] + args["deployment_suffix"]
    )
    zkevm_sequencer_url = "http://{}:{}".format(
        zkevm_sequencer_service.ip_address, zkevm_sequencer_service.ports["rpc"].number
    )
    zkevm_datastreamer_url = "{}:{}".format(
        zkevm_sequencer_service.ip_address,
        zkevm_sequencer_service.ports["data-streamer"].number,
    )

    zkevm_pool_manager_service = plan.get_service(
        name="zkevm-pool-manager" + args["deployment_suffix"]
    )
    zkevm_pool_manager_url = "http://{}:{}".format(
        zkevm_pool_manager_service.ip_address,
        zkevm_pool_manager_service.ports["http"].number,
    )
    config_artifact = plan.render_templates(
        name="cdk-erigon-rpc-config-artifact",
        config={
            "config.yaml": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/cdk-erigon/config.yml"
                ),
                data={
                    "zkevm_sequencer_url": zkevm_sequencer_url,
                    "zkevm_datastreamer_url": zkevm_datastreamer_url,
                    "is_sequencer": False,
                    "pool_manager_url": zkevm_pool_manager_url,
                    # common
                    "consensus_contract_type": args["consensus_contract_type"],
                    "l1_sync_start_block": 1 if args["anvil_state_file"] else 0,
                    "prometheus_port": args["prometheus_port"],
                    "zkevm_executor_port_number": zkevm_prover.EXECUTOR_PORT_NUMBER,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    _run(plan, args, CDK_ERIGON_TYPE.rpc, config_artifact)


def _run(plan, args, type, config_artifact):
    if type not in [
        CDK_ERIGON_TYPE.sequencer,
        CDK_ERIGON_TYPE.rpc,
    ]:
        fail("Unknown cdk-erigon type: {}".format(type))

    # Sequencer-specific configuration
    files = {}
    ports = {}
    if type == CDK_ERIGON_TYPE.sequencer:
        # Datadir configuration
        datadir = None
        if args.get("erigon_datadir_archive") != None:
            datadir = plan.upload_files(
                src=args.get("erigon_datadir_archive"),
            )
        else:
            datadir = Directory(
                persistent_key="cdk-erigon-datadir{}".format(args["deployment_suffix"]),
            )
        files[
            "/home/erigon/data/dynamic-{}-sequencer".format(args.get("chain_name"))
        ] = datadir

        ports[DATA_STREAMER_PORT_ID] = PortSpect(
            DATA_STREAMER_PORT_NUMBER, application_protocol="datastream"
        )

    # Chain artifacts
    chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-{}-chain-spec-artifact".format(type),
        config={
            "dynamic-{}-chainspec.json".format(args.get("chain_name")): struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/cdk-erigon/chainspec.json"
                ),
                data={
                    "chain_id": args.get("zkevm_rollup_chain_id"),
                    "enable_normalcy": args.get("enable_normalcy"),
                    "chain_name": args.get("chain_name"),
                },
            ),
        },
    )
    chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-config",
    )
    chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-allocs",
    )
    chain_first_batch_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-first-batch",
    )
    chain_artifacts = [
        chain_spec_artifact,
        chain_config_artifact,
        chain_allocs_artifact,
        chain_first_batch_artifact,
    ]

    proc_runner_file_artifact = plan.upload_files(
        name="cdk-erigon-" + type + "-proc-runner",
        src="../../../static_files/scripts/proc-runner.sh",
    )

    plan.add_service(
        name="cdk-erigon-{}{}".format(type, args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("cdk_erigon_image"),
            env_vars={
                "CDK_ERIGON_SEQUENCER": "1"
                if type == CDK_ERIGON_TYPE.sequencer
                else "0",
            },
            files={
                "/etc/cdk-erigon": Directory(
                    artifact_names=[config_artifact.config] + chain_artifacts,
                ),
                "/home/erigon/dynamic-configs/": Directory(
                    artifact_names=chain_artifacts,
                ),
                "/usr/local/share/proc-runner": proc_runner_file_artifact,
            }
            | files,
            ports={
                HTTP_RPC_PORT_ID: PortSpec(HTTP_RPC_PORT_NUMBER),
                WS_RPC_PORT_ID: PortSpec(WS_RPC_PORT_NUMBER, application_protocol="ws"),
                PPROF_PORT_ID: PortSpec(PPROF_PORT_NUMBER, wait=None),
                METRICS_PORT_ID: PortSpec(METRICS_PORT_NUMBER, wait=None),
            }
            | ports,
            entrypoint=["/usr/local/share/proc-runner/proc-runner.sh"],
            cmd=["cdk-erigon --config /etc/cdk-erigon/config.yaml"],
            user=User(uid=0, gid=0),
        ),
    )
