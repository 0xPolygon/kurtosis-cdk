ports = import_module("../shared/ports.star")
zkevm_prover = import_module("./zkevm_prover.star")


CDK_ERIGON_TYPE = struct(
    sequencer="sequencer",
    rpc="rpc",
)


# Port identifiers and numbers.
DATA_STREAMER_PORT_ID = "data-streamer"
DATA_STREAMER_PORT_NUMBER = 6900

PPROF_PORT_ID = "pprof"
PPROF_PORT_NUMBER = 6060

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
    return _run(plan, args, CDK_ERIGON_TYPE.sequencer, config_artifact)


def run_rpc(
    plan,
    args,
    contract_setup_addresses,
    sequencer_url,
    datastreamer_url,
    pool_manager_url,
):
    config_artifact = plan.render_templates(
        name="cdk-erigon-rpc-config-artifact",
        config={
            "config.yaml": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/cdk-erigon/config.yml"
                ),
                data={
                    "zkevm_sequencer_url": sequencer_url,
                    "zkevm_datastreamer_url": datastreamer_url,
                    "is_sequencer": False,
                    "pool_manager_url": pool_manager_url,
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
    return _run(plan, args, CDK_ERIGON_TYPE.rpc, config_artifact)


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

        ports[DATA_STREAMER_PORT_ID] = PortSpec(
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

    return plan.add_service(
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
                    artifact_names=[config_artifact] + chain_artifacts,
                ),
                "/home/erigon/dynamic-configs/": Directory(
                    artifact_names=chain_artifacts,
                ),
                "/usr/local/share/proc-runner": proc_runner_file_artifact,
            }
            | files,
            ports={
                ports.HTTP_RPC_PORT_ID: PortSpec(
                    ports.HTTP_RPC_PORT_NUMBER, application_protocol="http"
                ),
                ports.WS_RPC_PORT_ID: PortSpec(
                    ports.WS_RPC_PORT_NUMBER, application_protocol="ws"
                ),
                PPROF_PORT_ID: PortSpec(PPROF_PORT_NUMBER, wait=None),
                METRICS_PORT_ID: PortSpec(METRICS_PORT_NUMBER, wait=None),
            }
            | ports,
            entrypoint=["/usr/local/share/proc-runner/proc-runner.sh"],
            cmd=["cdk-erigon --config /etc/cdk-erigon/config.yaml"],
            user=User(uid=0, gid=0),
        ),
    )
