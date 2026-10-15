constants = import_module("../../package_io/constants.star")
ports_package = import_module("../shared/ports.star")
ports_util = import_module("../../package_io/ports.star")

SERVICE_NAME = "besu"

P2P_PORT_ID = "p2p"
P2P_PORT_NUMBER = 30303

METRICS_PORT_ID = "prometheus"
METRICS_PORT_NUMBER = 9545

GENESIS_INPUT_DIR = "/opt/besu-genesis-input"
GENESIS_ALLOCS_DIR = "/opt/besu-genesis-allocs"
GENESIS_OUTPUT_DIR = "/opt/besu-genesis-output"
CONFIG_DIR = "/etc/besu"
DATA_DIR = "/data"


# Builds the QBFT genesis (sovereign predeploys + funded accounts) and the validator node key,
# then starts the single Besu validator. Must run after the sovereign predeployed genesis has been
# created by the contracts service, and before the rollup is initialized on L1.
def run(plan, args):
    (genesis_artifact, key_artifact) = _build_genesis(plan, args)

    (ports, public_ports) = _get_ports(args)
    return plan.add_service(
        name=SERVICE_NAME + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["besu_image"],
            files={
                CONFIG_DIR: Directory(
                    artifact_names=[genesis_artifact, key_artifact],
                ),
                DATA_DIR: Directory(
                    persistent_key="besu-data" + args["deployment_suffix"],
                ),
            },
            ports=ports,
            public_ports=public_ports,
            cmd=[
                "--genesis-file=" + CONFIG_DIR + "/genesis.json",
                "--data-path=" + DATA_DIR,
                "--node-private-key-file=" + CONFIG_DIR + "/key",
                "--rpc-http-enabled",
                "--rpc-http-host=0.0.0.0",
                "--rpc-http-port={}".format(ports_package.HTTP_RPC_PORT_NUMBER),
                "--rpc-http-api=ETH,NET,WEB3,QBFT,TXPOOL,DEBUG,TRACE",
                "--rpc-http-cors-origins=*",
                "--rpc-ws-enabled",
                "--rpc-ws-host=0.0.0.0",
                "--rpc-ws-port={}".format(ports_package.WS_RPC_PORT_NUMBER),
                "--rpc-ws-api=ETH,NET,WEB3,QBFT,TXPOOL",
                "--host-allowlist=*",
                # The chain has a zero base fee, so the pool must accept zero-priced transactions.
                "--min-gas-price=0",
                # Single validator: there is nobody to discover, but the p2p stack itself has to
                # stay enabled because the QBFT engine only starts once the network layer is up.
                "--discovery-enabled=false",
                "--sync-mode=FULL",
                "--metrics-enabled",
                "--metrics-host=0.0.0.0",
                "--metrics-port={}".format(METRICS_PORT_NUMBER),
                "--logging=" + args["log_level"].upper(),
            ],
        ),
    )


def _build_genesis(plan, args):
    genesis_input_artifact = plan.render_templates(
        name="besu-genesis-input{}".format(args["deployment_suffix"]),
        config={
            "genesis-base.json": struct(
                template=read_file(
                    src="../../../static_files/chain/besu/genesis-base.json"
                ),
                data=args,
            ),
            "build-genesis.sh": struct(
                template=read_file(
                    src="../../../static_files/chain/besu/build-genesis.sh"
                ),
                data=args,
            ),
        },
    )
    predeployed_allocs_artifact = plan.get_files_artifact(
        name="predeployed_allocs.json",
    )

    result = plan.run_sh(
        name="build-besu-genesis",
        description="Building the Besu QBFT genesis and validator key",
        image=constants.TOOLBOX_IMAGE,
        files={
            GENESIS_INPUT_DIR: genesis_input_artifact,
            GENESIS_ALLOCS_DIR: predeployed_allocs_artifact,
        },
        run="chmod +x {0}/build-genesis.sh && {0}/build-genesis.sh".format(
            GENESIS_INPUT_DIR
        ),
        store=[
            StoreSpec(
                src=GENESIS_OUTPUT_DIR + "/genesis.json",
                name="besu-genesis" + args["deployment_suffix"],
            ),
            StoreSpec(
                src=GENESIS_OUTPUT_DIR + "/key",
                name="besu-node-key" + args["deployment_suffix"],
            ),
        ],
    )

    artifact_count = len(result.files_artifacts)
    if artifact_count != 2:
        fail(
            "The Besu genesis build should have generated 2 artifacts, got {}.".format(
                artifact_count
            )
        )
    return (result.files_artifacts[0], result.files_artifacts[1])


def _get_ports(args):
    ports = {
        ports_package.HTTP_RPC_PORT_ID: PortSpec(
            ports_package.HTTP_RPC_PORT_NUMBER, application_protocol="http"
        ),
        ports_package.WS_RPC_PORT_ID: PortSpec(
            ports_package.WS_RPC_PORT_NUMBER, application_protocol="ws"
        ),
        P2P_PORT_ID: PortSpec(P2P_PORT_NUMBER, wait=None),
        METRICS_PORT_ID: PortSpec(METRICS_PORT_NUMBER, wait=None),
    }
    public_ports = ports_util.get_public_ports(ports, "besu_start_port", args)
    return (ports, public_ports)
