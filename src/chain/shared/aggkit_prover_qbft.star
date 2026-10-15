besu = import_module("../besu/besu.star")

SERVICE_NAME = "aggkit-prover-qbft"

# Port identifiers and numbers.
GRPC_PORT_ID = "grpc"
GRPC_PORT_NUMBER = 4446

METRICS_PORT_ID = "metrics"
METRICS_PORT_NUMBER = 9093

CONFIG_DIR = "/etc/aggkit-prover-qbft"


# Starts aggkit-prover-qbft, the aggchain prover of consensus_contract_type 'qbft'. It refuses to
# start until AggchainQBFT is initialized and its chainConfigHash() matches the L2 (chain id, epoch
# length, starting block hash), and only binds its gRPC port after that check, so the port wait
# below is also the "chain config verified" gate.
def run(plan, args, contract_setup_addresses, sovereign_contract_setup_addresses):
    config_artifact = plan.render_templates(
        name="aggkit-prover-qbft-config{}".format(args["deployment_suffix"]),
        config={
            "config.toml": struct(
                template=read_file(
                    src="../../../static_files/chain/shared/aggkit-prover-qbft/config.toml"
                ),
                data={
                    "log_level": args["log_level"],
                    "log_format": args["log_format"],
                    "grpc_port_number": GRPC_PORT_NUMBER,
                    "metrics_port_number": METRICS_PORT_NUMBER,
                    "l2_network_id": args["l2_network_id"],
                    "max_headers_per_proof": args[
                        "aggkit_prover_qbft_max_headers_per_proof"
                    ],
                    "primary_prover": args["aggkit_prover_primary_prover"],
                    "sp1_cluster_endpoint": args["sp1_cluster_endpoint"],
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "aggkit", args["l1_rpc_url"]
                    ),
                    "l2_el_rpc_url": args["l2_el_rpc_url"],
                    "rollup_manager_address": contract_setup_addresses[
                        "rollup_manager_address"
                    ],
                    "global_exit_root_address": sovereign_contract_setup_addresses[
                        "sovereign_ger_proxy_addr"
                    ],
                    "header_fetch_concurrency": args[
                        "aggkit_prover_qbft_header_fetch_concurrency"
                    ],
                },
            )
        },
    )
    genesis_artifact = plan.get_files_artifact(name=besu.genesis_artifact_name(args))

    return plan.add_service(
        name=SERVICE_NAME + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["aggkit_prover_qbft_image"],
            files={
                CONFIG_DIR: Directory(
                    artifact_names=[config_artifact, genesis_artifact],
                ),
            },
            ports={
                GRPC_PORT_ID: PortSpec(
                    GRPC_PORT_NUMBER,
                    application_protocol="grpc",
                    wait="2m",
                ),
                METRICS_PORT_ID: PortSpec(
                    METRICS_PORT_NUMBER,
                    application_protocol="http",
                    wait=None,
                ),
            },
            env_vars={
                "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
                "RUST_BACKTRACE": "1",
            },
            entrypoint=["/usr/local/bin/aggkit-prover-qbft"],
            cmd=["run", "--cfg", CONFIG_DIR + "/config.toml"],
        ),
    )
