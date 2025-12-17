op_succinct = import_module("../op-geth/op_succinct_proposer.star")


# Port identifiers and numbers.
GRPC_PORT_ID = "grpc"
GRPC_PORT_NUMBER = 4446

METRICS_PORT_ID = "metrics"
METRICS_PORT_NUMBER = 9093


def run(plan, args, contract_setup_addresses, sovereign_contract_setup_addresses):
    aggkit_version = args.get("aggkit_prover_image").split(":")[1]
    aggkit_legacy = False
    if any([aggkit_version.startswith(x) for x in ("1.0", "1.1", "1.2")]):
        aggkit_legacy = True

    config_artifact = plan.render_templates(
        name="aggkit-prover-config",
        config={
            "config.toml": struct(
                template=read_file(
                    src="../../../static_files/aggkit-prover/config.toml"
                ),
                data={
                    "log_level": args.get("log_level"),
                    "log_format": args.get("log_format"),
                    # ports
                    "aggkit_prover_grpc_port": args["aggkit_prover_grpc_port"],
                    "metrics_port": args["aggkit_prover_metrics_port"],
                    # prover settings (fork12+)
                    "primary_prover": args["aggkit_prover_primary_prover"],
                    # L1
                    # TODO: Is it the right way of creating the L1_RPC_URL for aggkit related component ?
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "aggkit", args["l1_rpc_url"]
                    ),
                    # L2
                    "l2_el_rpc_url": args["op_el_rpc_url"],
                    "l2_cl_rpc_url": args["op_cl_rpc_url"],
                    "rollup_manager_address": contract_setup_addresses[
                        "zkevm_rollup_manager_address"
                    ],  # TODO: Check if it's the right address - is it the L1 rollup manager address ?
                    "global_exit_root_address": sovereign_contract_setup_addresses[
                        "sovereign_ger_proxy_addr"
                    ],  # TODO: Check if it's the right address - is it the L2 sovereign global exit root address ?
                    # TODO: For op-succinct, agglayer/op-succinct is currently on the golang version. This might change if we move to the rust version.
                    "proposer_url": "http://op-succinct-proposer{}:{}".format(
                        args["deployment_suffix"],
                        op_succinct.GRPC_PORT_NUMBER,
                    ),
                    # TODO: For legacy op, this would be different - something like http://op-proposer-001:8560
                    # "proposer_url": "http://op-proposer{}:{}".format(
                    #     args["deployment_suffix"], args["op_proposer_port"]
                    # ),
                    "network_id": args["zkevm_rollup_id"],
                    "sp1_cluster_endpoint": args["sp1_cluster_endpoint"],
                    "op_succinct_mock": args["op_succinct_mock"],
                    "aggkit_legacy": aggkit_legacy,
                },
            )
        },
    )

    evm_sketch_genesis_conf = _get_evm_sketch_genesis(plan, args)

    plan.add_service(
        name="aggkit-prover{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("aggkit_prover_image"),
            files={
                "/etc/aggkit-prover": Directory(
                    artifact_names=[
                        config_artifact,
                        evm_sketch_genesis_conf,
                    ]
                ),
            },
            ports={
                GRPC_PORT_ID: PortSpec(
                    GRPC_PORT_NUMBER,
                    application_protocol="grpc",
                ),
                METRICS_PORT_ID: PortSpec(
                    METRICS_PORT_NUMBER,
                    application_protocol="http",
                ),
            },
            env_vars={
                "PROPOSER_NETWORK_PRIVATE_KEY": args.get("sp1_prover_key"),
                "NETWORK_PRIVATE_KEY": args.get("sp1_prover_key"),
                "RUST_LOG": "info,aggkit_prover=debug,prover=debug,aggchain=debug",
                "RUST_BACKTRACE": "1",
            },
            entrypoint=[
                "/usr/local/bin/aggkit-prover",
            ],
            cmd=["run", "--config-path", "/etc/aggkit-prover/config.toml"],
        ),
    )


# Fetch the parsed .config section of L1 geth genesis.
def _get_evm_sketch_genesis(plan, args):
    # Upload file to files artifact
    evm_sketch_genesis_conf_artifact = plan.store_service_files(
        service_name="temp-contracts",
        name="evm-sketch-genesis-conf-artifact.json",
        src="/opt/op-succinct/evm-sketch-genesis.json",
        description="Storing evm-sketch-genesis.json for evm-sketch-genesis field in aggkit-prover.",
    )

    # Fetch evm-sketch-genesis-conf artifact
    evm_sketch_genesis_conf = plan.get_files_artifact(
        name="evm-sketch-genesis-conf-artifact.json",
        description="Fetch evm-sketch-genesis-conf-artifact.json files artifact",
    )

    # Remove temp-contracts service after extracting evm-sketch-genesis
    plan.remove_service(
        name="temp-contracts",
        description="Remove temp-contracts service after extracting evm-sketch-genesis",
    )
    return evm_sketch_genesis_conf
