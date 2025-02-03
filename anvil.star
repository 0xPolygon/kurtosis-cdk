ANVIL_IMAGE = "ghcr.io/foundry-rs/foundry:latest"
ANVIL_PORT = 8545
ANVIL_BLOCK_TIME = 1
ANVIL_SLOTS_IN_AN_EPOCH = (
    2  # Setting to X leads to block N-(X+1) being finalized, being N latest block
)


def run(plan, args):
    chain_id = str(args["l1_chain_id"])

    plan.add_service(
        name="anvil",
        config=ServiceConfig(
            image=ANVIL_IMAGE,
            ports={
                "rpc": PortSpec(ANVIL_PORT, application_protocol="http"),
            },
            cmd=[
                "anvil --block-time "
                + str(ANVIL_BLOCK_TIME)
                + " --slots-in-an-epoch "
                + str(ANVIL_SLOTS_IN_AN_EPOCH)
                + " --chain-id "
                + chain_id
                + " --host 0.0.0.0 --port "
                + str(ANVIL_PORT)
            ],
        ),
        description="Anvil",
    )

    mnemonic = args.get("l1_preallocated_mnemonic")
    cmd = (
        'cast rpc anvil_setBalance $(cast wallet addr --mnemonic "'
        + mnemonic
        + '") 0x33b2e3c9fd0803ce8000000'
    )
    plan.exec(
        description="Funding L1 account",
        service_name="anvil",
        recipe=ExecRecipe(command=["/bin/sh", "-c", cmd]),
    )

    # Check balance
    plan.exec(
        description="Checking L1 account balance",
        service_name="anvil",
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                'cast balance $(cast wallet addr --mnemonic "' + mnemonic + '")',
            ]
        ),
    )
