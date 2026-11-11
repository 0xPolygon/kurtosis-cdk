constants = import_module("../../package_io/constants.star")
ports_package = import_module("../shared/ports.star")


# Where the rendered geth-genesis artifact is mounted inside the container.
GENESIS_PATH = "/genesis"
GENESIS_FILE = "l2-anvil-genesis.json"


def run(plan, args, genesis_artifact):
    """Start the L2 anvil node seeded with the sovereign predeployed allocs.

    Called from main.star between create_sovereign_predeployed_genesis() and
    init_rollup(): the allocs must exist before the node boots, and the node must
    be live before initialize_rollup funds accounts and checks the L2 contracts.
    """
    service_name = (
        constants.L2_RPC_MAPPING[constants.SEQUENCER_TYPE.anvil]
        + args["deployment_suffix"]
    )

    # --dump-state is not passed: anvil rejects it together with --init. State is
    # captured through the anvil_dumpState RPC instead.
    # --timestamp $(date +%s) is required: the image entrypoint is
    # ["/bin/sh","-c"], so the substitution runs in the container. Without it the
    # chain inherits the genesis timestamp (0) and runs in 1970.
    cmd = (
        "anvil --block-time "
        + str(args["l2_anvil_block_time"])
        + " --slots-in-an-epoch "
        + str(args["l2_anvil_slots_in_epoch"])
        + " --chain-id "
        + str(args["l2_chain_id"])
        + " --host 0.0.0.0 --port "
        + str(ports_package.HTTP_RPC_PORT_NUMBER)
        + " --balance "
        + str(args["l2_anvil_balance"])
        + ' --mnemonic "'
        + constants.ANVIL_DEFAULT_MNEMONIC
        + '"'
        + " --init "
        + GENESIS_PATH
        + "/"
        + GENESIS_FILE
        + " --timestamp $(date +%s)"
    )

    plan.add_service(
        name=service_name,
        config=ServiceConfig(
            image=args["anvil_image"],
            ports={
                ports_package.HTTP_RPC_PORT_ID: PortSpec(
                    ports_package.HTTP_RPC_PORT_NUMBER, application_protocol="http"
                ),
            },
            files={GENESIS_PATH: genesis_artifact},
            cmd=[cmd],
        ),
    )

    # Same shape as the op-reth L2 URL, resolvable inside the enclave network.
    return "http://{}:{}".format(service_name, ports_package.HTTP_RPC_PORT_NUMBER)
