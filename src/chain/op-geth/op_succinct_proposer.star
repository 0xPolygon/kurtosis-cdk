constants = import_module("../../package_io/constants.star")


# Port identifiers and numbers.
GRPC_PORT_ID = "grpc"
GRPC_PORT_NUMBER = 50051

METRICS_PORT_ID = "prometheus"
METRICS_PORT_NUMBER = 8080


def run(plan, args):
    l1_genesis_artifact = plan.get_files_artifact(
        name="el_cl_genesis_data_for_op_succinct",
    )

    plan.add_service(
        name="op-succinct-proposer" + args.get("deployment_suffix"),
        config=ServiceConfig(
            image=args.get("op_succinct_proposer_image"),
            ports={
                METRICS_PORT_ID: PortSpec(
                    METRICS_PORT_NUMBER,
                    wait="60s",
                ),
                GRPC_PORT_ID: PortSpec(
                    GRPC_PORT_NUMBER,
                    application_protocol="grpc",
                    wait="60s",
                ),
            },
            env_vars={
                "L1_RPC": args.get("l1_rpc_url"),
                "L1_BEACON_RPC": args.get("l1_beacon_url"),
                "L2_RPC": args.get("op_el_rpc_url"),
                "L2_NODE_RPC": args.get("op_cl_rpc_url"),
                # TODO understand why the PRIVATE_KEY needs to be set and if it actually need to be the sequencer key... The value 0xc797616a567ffd3f7d80f110f4c19900e55258ac2aa96d96ded790e0bd727458 is made up just to ensure that the value isn't needed
                "PRIVATE_KEY": "0xc797616a567ffd3f7d80f110f4c19900e55258ac2aa96d96ded790e0bd727458",
                "ETHERSCAN_API_KEY": "",
                "VERIFIER_ADDRESS": args.get("agglayer_gateway_address"),
                "AGG_PROOF_MODE": args.get("op_succinct_agg_proof_mode"),
                "L2OO_ADDRESS": args.get("zkevm_rollup_address"),
                "OP_SUCCINCT_MOCK": args.get("op_succinct_mock"),
                "AGGLAYER": args.get(
                    "op_succinct_agglayer"
                ),  # agglayer/op-succinct specific.
                "GRPC_ADDRESS": "0.0.0.0:{}".format(
                    GRPC_PORT_NUMBER
                ),  # agglayer/op-succinct specific.
                "NETWORK_PRIVATE_KEY": args.get("sp1_prover_key"),
                "MAX_CONCURRENT_PROOF_REQUESTS": args.get(
                    "op_succinct_max_concurrent_proof_requests"
                ),
                "MAX_CONCURRENT_WITNESS_GEN": args.get(
                    "op_succinct_max_concurrent_witness_gen"
                ),
                "RANGE_PROOF_INTERVAL": args.get("op_succinct_range_proof_interval"),
                "DATABASE_URL": "postgres://op_succinct_user:op_succinct_password@postgres"
                + args.get("deployment_suffix")
                + ":5432/op_succinct_db",
                "PROVER_ADDRESS": args.get("l2_sequencer_address"),
                "METRICS_PORT": str(METRICS_PORT_NUMBER),
                # "DGF_ADDRESS": "", # Address of the DisputeGameFactory contract. Note: If set, the proposer will create a dispute game with the DisputeGameFactory, rather than the OPSuccinctL2OutputOracle. Compatible with OptimismPortal2.
                # "LOOP_INTERVAL": 60, # Default: 60. The interval (in seconds) between each iteration of the OP Succinct service.
                # "SAFE_DB_FALLBACK": False, # Default: false. Whether to fallback to timestamp-based L1 head estimation even though SafeDB is not activated for op-node. When false, proposer will panic if SafeDB is not available. It is by default false since using the fallback mechanism will result in higher proving cost.
                # "SIGNER_URL": "", # URL for the Web3Signer. Note: This takes precedence over the `PRIVATE_KEY` environment variable.
                # "SIGNER_ADDRESS": "", # Address of the account that will be posting output roots to L1. Note: Only set this if the signer is a Web3Signer. Note: Required if `SIGNER_URL` is set.
                # Kurtosis CDK specific - required to see logs in the op-succinct-proposer after https://github.com/agglayer/op-succinct/commit/892085405a65a2b1c245beca3dcb9d9f5626af0e commit
                # Kurtosis CDK specific - https://github.com/agglayer/op-succinct/commit/cffd968bd744cddc262543e1195fdd36110ecf83
                "RUST_LOG": args.get("log_level"),
                "LOG_FORMAT": args.get("log_format"),
            },
            files={
                # Mount L1 genesis file.
                # The op-succinct binary runs from /app working directory (see Dockerfile)
                # It looks for configs/L1/{chainId}.json relative to working directory
                "/app/configs/L1": Directory(artifact_names=[l1_genesis_artifact])
            },
        ),
    )


def extract_fetch_l2oo_config(plan, args):
    cmds = [
        # Check for fetch-l2oo-config (newer) or fetch-rollup-config (legacy) binary
        "BINARY_PATH=$(ls /usr/local/bin/fetch-l2oo-config 2>/dev/null || ls /usr/local/bin/fetch-rollup-config 2>/dev/null || (echo 'No compatible binary found'; exit 1))",
        'echo "Found binary at: $BINARY_PATH"',
        'cp "$BINARY_PATH" /tmp/fetch-l2oo-config',
        "echo 'Successfully extracted fetch-l2oo-config binary'",
    ]
    plan.run_sh(
        description="Extract fetch-l2oo-config binary",
        image=args.get("op_succinct_proposer_image"),
        run=" && ".join(cmds),
        store=[
            StoreSpec(
                src="/tmp/fetch-l2oo-config",
                name="fetch-l2oo-config",
            )
        ],
    )


def create_evm_sketch_genesis(plan, args):
    parse_evm_sketch_genesis_artifact = plan.render_templates(
        name="parse-evm-sketch-genesis.sh",
        config={
            "parse-evm-sketch-genesis.sh": struct(
                template=read_file(
                    src="../../../templates/op-succinct/parse-evm-sketch-genesis.sh"
                ),
                data=args,
            ),
        },
        description="Create parse-evm-sketch-genesis.sh files artifact",
    )

    op_geth_genesis = plan.store_service_files(
        service_name="op-el-1-op-geth-op-node" + args["deployment_suffix"],
        name="op_geth_genesis.json",
        src="/network-configs/genesis-" + str(args["zkevm_rollup_chain_id"]) + ".json",
        description="Storing OP Geth genesis.json for evm-sketch-genesis field in aggkit-prover.",
    )

    # Add a temporary service using the contracts image
    temp_service_name = "temp-contracts"

    files = {}
    files["/opt/op-succinct/"] = Directory(artifact_names=[op_geth_genesis])

    files[constants.SCRIPTS_DIR] = Directory(
        artifact_names=[parse_evm_sketch_genesis_artifact]
    )

    # Create helper service to deploy contracts
    plan.add_service(
        name=temp_service_name,
        config=ServiceConfig(
            image=args["agglayer_contracts_image"],
            files=files,
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )

    # Parse .config section of L1 geth genesis for evm-sketch-genesis input
    plan.exec(
        description="Parsing .config section of L1 geth genesis for evm-sketch-genesis input",
        service_name="temp-contracts",
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "cp {1}/parse-evm-sketch-genesis.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                    "/opt/op-succinct/parse-evm-sketch-genesis.sh",
                    constants.SCRIPTS_DIR,
                ),
            ]
        ),
    )
