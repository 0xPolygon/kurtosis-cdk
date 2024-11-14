FOUNDRY_IMAGE = (
    "ghcr.io/foundry-rs/foundry:nightly-2044faec64f99a21f0e5f0094458a973612d0712"
)


def run(plan, args):
    state_artifact = plan.render_templates(
        name="anvil-state",
        config={
            "state.json": struct(
                template=read_file(src="./templates/contract-deploy/anvil-state.json"),
                data={},
            )
        },
    )
    plan.add_service(
        name="anvil" + args["deployment_suffix"],
        config=ServiceConfig(
            image=FOUNDRY_IMAGE,
            ports={
                "rpc": PortSpec(number=8545),
            },
            files={"/etc/anvil": state_artifact},
            entrypoint=["anvil"],
            cmd=[
                "--chain-id",
                str(args["l1_chain_id"]),
                "--mnemonic",
                args["l1_preallocated_mnemonic"],
                "--balance",
                "1000000000",
                # To speed up the finalization of blocks, you can use the --slots-in-an-epoch flag
                # with a value of 1 for example. This will lead to the block at height N-2 being
                # finalized, where N is the latest block.
                "--slots-in-an-epoch",
                "--host",
                "0.0.0.0",
                "--port",
                "8545",
                "--state",
                "/etc/anvil",
            ],
        ),
    )
