constants = import_module("../../package_io/constants.star")
ports_package = import_module("../shared/ports.star")


# Where the rendered geth-genesis artifact is mounted inside the container.
GENESIS_PATH = "/genesis"
GENESIS_FILE = "l2-anvil-genesis.json"


def run(plan, args, genesis_artifact):
    """Start the L2 anvil node seeded with the sovereign predeployed allocs.

    Called from main.star BETWEEN create_sovereign_predeployed_genesis() and
    init_rollup(): the allocs must exist before the node boots, and the node
    must be live before initialize_rollup funds accounts and bytecode-checks
    the L2 contracts (static_files/contracts/contracts.sh:808-810, 942).
    """
    service_name = constants.L2_RPC_MAPPING[constants.SEQUENCER_TYPE.anvil] + args[
        "deployment_suffix"
    ]

    # NOTE: --dump-state is intentionally absent. anvil rejects `--init`
    # together with `--dump-state` ("the argument '--init <PATH>' cannot be
    # used with '--dump-state <PATH>'"); re-verified on v1.4.3 and v1.5.1 in
    # plans/dev-ui-ci-snapshot/s4b-evidence/15-init-dumpstate-check.txt.
    # Snapshot capture uses the anvil_dumpState RPC instead.
    # NOTE: --timestamp $(date +%s) is required. The image entrypoint is
    # ["/bin/sh","-c"], so the substitution happens in-container. Without it
    # the chain inherits the genesis file's timestamp (0) and runs in 1970.
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
        + args["l2_anvil_mnemonic"]
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

    # Same string shape as src/chain/op-reth/launcher.star:26-30 so every
    # template that reads it resolves inside the enclave network.
    return "http://{}:{}".format(service_name, ports_package.HTTP_RPC_PORT_NUMBER)
