ports_package = import_module("../shared/ports.star")
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


def run_sequencer(plan, args, contract_setup_addresses, stateless_executor_url=None):
    return _run(
        plan,
        args,
        contract_setup_addresses,
        CDK_ERIGON_TYPE.sequencer,
        stateless_executor_url,
    )


def run_rpc(
    plan,
    args,
    contract_setup_addresses,
    sequencer_url,
    datastreamer_url,
    pool_manager_url,
):
    return _run(
        plan,
        args,
        contract_setup_addresses,
        CDK_ERIGON_TYPE.rpc,
        None,
        sequencer_url,
        datastreamer_url,
        pool_manager_url,
    )


def _run(
    plan,
    args,
    contract_setup_addresses,
    type,
    stateless_executor_url=None,
    sequencer_url=None,
    datastreamer_url=None,
    pool_manager_url=None,
):
    if type not in [
        CDK_ERIGON_TYPE.sequencer,
        CDK_ERIGON_TYPE.rpc,
    ]:
        fail("Unknown cdk-erigon type: {}".format(type))

    config_artifact = plan.render_templates(
        name="cdk-erigon-{}-config{}".format(type, args.get("deployment_suffix")),
        config={
            "config.yaml": struct(
                template=read_file(
                    src="../../../static_files/chain/cdk-erigon/cdk-erigon/config.yml"
                ),
                data={
                    "is_sequencer": type == CDK_ERIGON_TYPE.sequencer,
                    "consensus_contract_type": args.get("consensus_contract_type"),
                    "l1_sync_start_block": 1 if args.get("anvil_state_file") else 0,
                    # ports
                    "http_rpc_port_number": ports_package.HTTP_RPC_PORT_NUMBER,
                    "ws_rpc_port_number": ports_package.WS_RPC_PORT_NUMBER,
                    "executor_port_number": zkevm_prover.EXECUTOR_PORT_NUMBER,
                    "data_streamer_port_number": DATA_STREAMER_PORT_NUMBER,
                    "metrics_port_number": METRICS_PORT_NUMBER,
                    "pprof_port_number": PPROF_PORT_NUMBER,
                }
                | args
                | contract_setup_addresses
                | (
                    {
                        # rpc-specific configuration
                        "sequencer_url": sequencer_url,
                        "datastreamer_url": datastreamer_url,
                        "pool_manager_url": pool_manager_url,
                    }
                    if type == CDK_ERIGON_TYPE.rpc
                    else {}
                )
                | (
                    {
                        "stateless_executor_url": stateless_executor_url,
                    }
                    if args.get("erigon_strict_mode")
                    else {}
                ),
            ),
        },
    )

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
        name="cdk-erigon-{}-chain-spec{}".format(type, args.get("deployment_suffix")),
        config={
            "dynamic-{}-chainspec.json".format(args.get("chain_name")): struct(
                template=read_file(
                    src="../../../static_files/chain/cdk-erigon/cdk-erigon/chainspec.json"
                ),
                data={
                    "chain_id": args.get("l2_chain_id"),
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
        name="cdk-erigon-{}-proc-runner{}".format(type, args.get("deployment_suffix")),
        src="../../../static_files/scripts/proc-runner.sh",
    )

    result = plan.add_service(
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
                ports_package.HTTP_RPC_PORT_ID: PortSpec(
                    ports_package.HTTP_RPC_PORT_NUMBER, application_protocol="http"
                ),
                ports_package.WS_RPC_PORT_ID: PortSpec(
                    ports_package.WS_RPC_PORT_NUMBER, application_protocol="ws"
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

    # Return context
    http_rpc_url = result.ports[ports_package.HTTP_RPC_PORT_ID].url
    ws_rpc_url = result.ports[ports_package.WS_RPC_PORT_ID].url
    if type == CDK_ERIGON_TYPE.sequencer:
        datastreamer_url = result.ports[DATA_STREAMER_PORT_ID].url.removeprefix(
            "datastream://"
        )
        return struct(
            http_rpc_url=http_rpc_url,
            ws_rpc_url=ws_rpc_url,
            datastreamer_url=datastreamer_url,
        )
    else:
        return struct(
            http_rpc_url=http_rpc_url,
            ws_rpc_url=ws_rpc_url,
        )
