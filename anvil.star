FOUNDRY_IMAGE = (
    "ghcr.io/foundry-rs/foundry:nightly-2044faec64f99a21f0e5f0094458a973612d0712"
)


def run(plan, args):
    state_file = read_file(src="./templates/contract-deploy/pre-deployed-contracts/anvil-state.json")
    state_artifact = plan.render_templates(
        name="anvil-state",
        config={"state.json": struct(template=state_file, data={})},
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
                "--host",
                "0.0.0.0",
                "--port",
                "8545",
            ],
        ),
    )
