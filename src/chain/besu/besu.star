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
GENESIS_UNSEALED_DIR = "/opt/besu-genesis-unsealed"
GENESIS_VALIDATORS_DIR = "/opt/besu-genesis-validators"
CONFIG_DIR = "/etc/besu"
DATA_DIR = "/data"


# Name of the files artifact holding the Besu genesis.json, also mounted by aggkit-prover-qbft as its
# evm-sketch-genesis.
def genesis_artifact_name(args):
    return "besu-genesis" + args["deployment_suffix"]


# Builds the QBFT genesis (sovereign predeploys + funded accounts) and the node keys, then starts
# the chain. Must run after the sovereign predeployed genesis has been created by the contracts
# service, and before the rollup is initialized on L1.
#
# With besu_validator_count = 1 a single node is both validator and RPC endpoint. With more, the
# validators run as besu<suffix>-validator-<n> and a non-validator node named besu<suffix> serves
# RPC; the validators find each other through it (bootnode + discovery).
#
# Returns the service the other components talk to.
def run(plan, args):
    nodes = _build_genesis(plan, args)
    if args["besu_validator_count"] == 1:
        return _add_node(
            plan,
            args,
            name=SERVICE_NAME + args["deployment_suffix"],
            genesis_artifact=nodes.genesis,
            key_artifact=nodes.validator_keys[0],
            serves_rpc=True,
            single_node=True,
        )

    rpc_service = _add_node(
        plan,
        args,
        name=SERVICE_NAME + args["deployment_suffix"],
        genesis_artifact=nodes.genesis,
        key_artifact=nodes.rpc_key,
        serves_rpc=True,
        single_node=False,
    )
    bootnode = "enode://{}@{}:{}".format(
        nodes.rpc_enode_id, rpc_service.ip_address, P2P_PORT_NUMBER
    )
    for index, key_artifact in enumerate(nodes.validator_keys):
        _add_node(
            plan,
            args,
            name="{}{}-validator-{}".format(
                SERVICE_NAME, args["deployment_suffix"], _pad(index + 1)
            ),
            genesis_artifact=nodes.genesis,
            key_artifact=key_artifact,
            serves_rpc=False,
            single_node=False,
            bootnodes=bootnode,
        )

    # QBFT only produces blocks once a quorum of validators is peered, and the steps that follow
    # (funding, rollup initialization) send L2 transactions.
    plan.wait(
        service_name=SERVICE_NAME + args["deployment_suffix"],
        description="Waiting for the QBFT validators to produce blocks",
        recipe=PostHttpRequestRecipe(
            port_id=ports_package.HTTP_RPC_PORT_ID,
            endpoint="/",
            content_type="application/json",
            body='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}',
            extract={"block": ".result"},
        ),
        field="extract.block",
        assertion="!=",
        target_value="0x0",
        interval="2s",
        timeout="5m",
    )
    return rpc_service


def _add_node(
    plan,
    args,
    name,
    genesis_artifact,
    key_artifact,
    serves_rpc,
    single_node,
    bootnodes=None,
):
    is_qbft = args["consensus_contract_type"] == constants.CONSENSUS_TYPE.qbft
    (ports, public_ports) = _get_ports(args, serves_rpc)
    flags = [
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
        "--sync-mode=FULL",
        "--metrics-enabled",
        "--metrics-host=0.0.0.0",
        "--metrics-port={}".format(METRICS_PORT_NUMBER),
        "--logging=" + args["log_level"].upper(),
    ]
    if single_node:
        # Single validator: there is nobody to discover, but the p2p stack itself has to stay
        # enabled because the QBFT engine only starts once the network layer is up.
        flags.append("--discovery-enabled=false")
    elif bootnodes:
        flags.append("--bootnodes=" + bootnodes)
    if serves_rpc and is_qbft:
        flags += [
            # aggkit-prover-qbft builds EVM sketches with eth_getProof at past blocks, which Bonsai
            # only serves for a short window.
            "--data-storage-format=FOREST",
            # aggkit-prover-qbft fetches headers concurrently next to aggkit and the bridge
            # service; Besu closes connections past this limit (default 80).
            "--rpc-http-max-active-connections={}".format(
                args["besu_rpc_max_active_connections"]
            ),
        ]

    config_kwargs = {}
    if single_node:
        config_kwargs["cmd"] = flags
    else:
        # Peers must advertise an address the others can dial; Besu defaults to 127.0.0.1 and the
        # container IP is only known once the container runs.
        config_kwargs["entrypoint"] = ["/bin/bash", "-c"]
        config_kwargs["cmd"] = [
            'exec besu-entry.sh {} --p2p-host="$(hostname -i | cut -d" " -f1)"'.format(
                " ".join(["'{}'".format(flag) for flag in flags])
            )
        ]
        config_kwargs["env_vars"] = {"BESU_OPTS": "-Xmx" + args["besu_max_heap"]}

    return plan.add_service(
        name=name,
        config=ServiceConfig(
            image=args["besu_image"],
            files={
                CONFIG_DIR: Directory(
                    artifact_names=[genesis_artifact, key_artifact],
                ),
                # besu<suffix> keeps its original key, besu-data<suffix>.
                DATA_DIR: Directory(
                    persistent_key=name.replace(
                        SERVICE_NAME, SERVICE_NAME + "-data", 1
                    ),
                ),
            },
            ports=ports,
            public_ports=public_ports,
            **config_kwargs
        ),
    )


def _build_genesis(plan, args):
    suffix = args["deployment_suffix"]
    validator_count = args["besu_validator_count"]
    genesis_input_artifact = plan.render_templates(
        name="besu-genesis-input{}".format(suffix),
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
            "encode-extra-data.sh": struct(
                template=read_file(
                    src="../../../static_files/chain/besu/encode-extra-data.sh"
                ),
                data=args,
            ),
        },
    )
    predeployed_allocs_artifact = plan.get_files_artifact(
        name="predeployed_allocs.json",
    )

    # Node keys, validator set and the genesis without its extraData (toolbox: cast + jq).
    store = [
        StoreSpec(
            src=GENESIS_OUTPUT_DIR + "/genesis-without-extra-data.json",
            name="besu-genesis-unsealed" + suffix,
        ),
        StoreSpec(
            src=GENESIS_OUTPUT_DIR + "/validators.json",
            name="besu-genesis-validators" + suffix,
        ),
    ]
    for index in range(validator_count):
        store.append(
            StoreSpec(
                src="{}/validator-{}/key".format(GENESIS_OUTPUT_DIR, index + 1),
                name="besu-node-key{}-validator-{}".format(suffix, _pad(index + 1)),
            )
        )
    if validator_count > 1:
        store.append(
            StoreSpec(
                src=GENESIS_OUTPUT_DIR + "/rpc/key",
                name="besu-node-key" + suffix,
            )
        )
    result = plan.run_sh(
        name="build-besu-genesis",
        description="Building the Besu QBFT genesis and node keys",
        image=constants.TOOLBOX_IMAGE,
        files={
            GENESIS_INPUT_DIR: genesis_input_artifact,
            GENESIS_ALLOCS_DIR: predeployed_allocs_artifact,
        },
        run="bash {}/build-genesis.sh".format(GENESIS_INPUT_DIR),
        store=store,
    )
    if len(result.files_artifacts) != len(store):
        fail(
            "The Besu genesis build should have generated {} artifacts, got {}.".format(
                len(store), len(result.files_artifacts)
            )
        )
    validator_keys = result.files_artifacts[2 : 2 + validator_count]
    rpc_key = None
    if validator_count > 1:
        rpc_key = result.files_artifacts[2 + validator_count]

    # extraData with Besu's own RLP encoder.
    sealed = plan.run_sh(
        name="encode-besu-extra-data",
        description="Encoding the QBFT genesis extraData with besu rlp encode",
        image=args["besu_image"],
        files={
            GENESIS_INPUT_DIR: genesis_input_artifact,
            GENESIS_UNSEALED_DIR: result.files_artifacts[0],
            GENESIS_VALIDATORS_DIR: result.files_artifacts[1],
        },
        run="bash {}/encode-extra-data.sh".format(GENESIS_INPUT_DIR),
        store=[
            StoreSpec(
                src=GENESIS_OUTPUT_DIR + "/genesis.json",
                name=genesis_artifact_name(args),
            ),
        ],
    )

    # Enode id of the RPC node, the bootnode of the validators.
    rpc_enode_id = None
    if validator_count > 1:
        rpc_enode_id = plan.run_sh(
            name="read-besu-rpc-enode-id",
            description="Reading the enode id of the Besu RPC node",
            image=constants.TOOLBOX_IMAGE,
            run="cast wallet public-key --mnemonic '{}' --mnemonic-index {} | sed 's/^0x//' | tr -d '\\n'".format(
                args["l1_preallocated_mnemonic"],
                args["besu_validator_mnemonic_index_base"] + validator_count,
            ),
        ).output

    return struct(
        genesis=sealed.files_artifacts[0],
        validator_keys=validator_keys,
        rpc_key=rpc_key,
        rpc_enode_id=rpc_enode_id,
    )


def _pad(number):
    return "00{}".format(number)[-3:]


def _get_ports(args, serves_rpc):
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
    public_ports = {}
    if serves_rpc:
        public_ports = ports_util.get_public_ports(ports, "besu_start_port", args)
    return (ports, public_ports)
