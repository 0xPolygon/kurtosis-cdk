constants = import_module("../../package_io/constants.star")
databases = import_module("../shared/databases.star")
ports_package = import_module("../../package_io/ports.star")

AGGKIT_BINARY_NAME = "aggkit"

# Port identifiers and numbers.
RPC_PORT_ID = "rpc"
RPC_PORT_NUMBER = 5576

REST_API_PORT_ID = "rest"
REST_API_PORT_NUMBER = 5577

AGGREGATOR_PORT_ID = "aggregator"
AGGREGATOR_PORT_NUMBER = 50081


def run(plan, args, contract_setup_addresses, genesis_artifact):
    db_configs = databases.get_db_configs(
        args.get("deployment_suffix"), args.get("sequencer_type")
    )
    keystore_artifacts = get_keystore_artifacts(plan, args)
    agglayer_endpoint = get_agglayer_endpoint(plan, args)
    l2_rpc_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    config_artifact = plan.render_templates(
        name="cdk-node-config-artifact",
        config={
            "cdk-node-config.toml": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/cdk-node/config.toml"
                ),
                data=args
                | {
                    "is_validium_mode": args.get("consensus_contract_type")
                    == constants.CONSENSUS_TYPE.cdk_validium,
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "cdk-node", args["l1_rpc_url"]
                    ),
                    "l2_rpc_url": l2_rpc_url,
                    "agglayer_endpoint": agglayer_endpoint,
                    "aggregator_port_number": AGGREGATOR_PORT_NUMBER,
                }
                | db_configs
                | contract_setup_addresses,
            )
        },
    )

    # Build the service command
    # TODO: Simplify this when we have better support for arguments in Kurtosis
    cmd = "cdk-node run --cfg=/etc/cdk/cdk-node-config.toml --save-config-path=/tmp"

    components = "sequence-sender,aggregator"
    if args.get("binary_name") == AGGKIT_BINARY_NAME:
        components = "aggsender,bridge"
    if args["consensus_contract_type"] == constants.CONSENSUS_TYPE.pessimistic:
        components = "aggsender"
    cmd += " --components={}".format(components)

    if args.get("binary_name") != AGGKIT_BINARY_NAME:
        cmd += " --custom-network-file=/etc/cdk/genesis.json"

    plan.add_service(
        name="cdk-node{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("cdk_node_image"),
            files={
                "/etc/cdk": Directory(
                    artifact_names=[
                        config_artifact,
                        genesis_artifact,
                        keystore_artifacts.aggregator,
                        keystore_artifacts.sequencer,
                        keystore_artifacts.claim_sponsor,
                    ],
                ),
                "/data": Directory(
                    artifact_names=[],
                ),
            },
            ports={
                RPC_PORT_ID: PortSpec(
                    RPC_PORT_NUMBER,
                    application_protocol="http",
                    wait=None,
                ),
                REST_API_PORT_ID: PortSpec(
                    REST_API_PORT_NUMBER,
                    application_protocol="http",
                    wait=None,
                ),
            }
            | (
                {
                    AGGREGATOR_PORT_ID: PortSpec(
                        AGGREGATOR_PORT_NUMBER,
                        application_protocol="grpc",
                        wait="2m"
                        if not args.get("use_previously_deployed_contracts")
                        else None,
                    )
                }
                if args.get("consensus_contract_type")
                != constants.CONSENSUS_TYPE.pessimistic
                else {}
            ),
            entrypoint=["sh", "-c"],
            cmd=[" && ".join(["sleep 20", cmd])],
        ),
    )


# Function to allow cdk-node-config to pick whether to use agglayer_readrpc_port or agglayer_grpc_port depending on whether cdk-node or aggkit-node is being deployed.
# On aggkit/cdk-node point of view, only the agglayer_image version is important. Both services can work with both grpc/readrpc and this depends on the agglayer version.
# On Kurtosis point of view, we are checking whether the cdk-node or the aggkit node is being used to filter the grpc/readrpc.
def get_agglayer_endpoint(plan, args):
    if args.get("sequencer_type") == constants.SEQUENCER_TYPE.op_geth or (
        "0.3" in args.get("agglayer_image")
        and args.get("binary_name") == AGGKIT_BINARY_NAME
    ):
        return "grpc"
    return "readrpc"


def get_keystore_artifacts(plan, args):
    sequencer_keystore_artifact = plan.store_service_files(
        name="sequencer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/sequencer.keystore",
    )
    aggregator_keystore_artifact = plan.get_files_artifact(
        name="aggregator-keystore",
        # service_name="contracts" + args["deployment_suffix"],
        # src=constants.KEYSTORES_DIR+"/aggregator.keystore",
    )
    claim_sponsor_keystore_artifact = plan.store_service_files(
        name="claimsponsor-keystore-cdk",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/claimsponsor.keystore",
    )
    return struct(
        sequencer=sequencer_keystore_artifact,
        aggregator=aggregator_keystore_artifact,
        claim_sponsor=claim_sponsor_keystore_artifact,
    )
