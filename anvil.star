STATE_PATH = "/tmp/state"
GENESIS_PATH = "/tmp/genesis"


def run(plan, anvil_config):
    chain_id = str(anvil_config["chain_id"])
    block_time = anvil_config["block_time"]
    slots_in_epoch = anvil_config["slots_in_epoch"]
    genesis_artifact_ref = anvil_config.get("genesis_artifact_ref")
    service_files = {}
    mnemonic = anvil_config["preallocated_mnemonic"]
    state_file = anvil_config["state_file"]
    image = anvil_config["image"]
    name = anvil_config["name"]
    port = anvil_config["port"]

    cmd = (
        "anvil --block-time "
        + str(block_time)
        + " --slots-in-an-epoch "
        + str(slots_in_epoch)
        + " --chain-id "
        + chain_id
        + " --host 0.0.0.0 --port "
        + str(port)
        + " --balance 1000000000"
        + ' --mnemonic "'
        + mnemonic
        + '"'
    )

    # You can't use --init and --load-state/--dump-state at same time.
    if genesis_artifact_ref:
        genesis_artifact = plan.get_files_artifact(name=genesis_artifact_ref)
        service_files[GENESIS_PATH] = genesis_artifact
        cmd += " --init " + GENESIS_PATH + "/" + genesis_artifact_ref
    else:
        cmd += " --dump-state " + STATE_PATH + "/state_out.json"
        if bool(state_file):
            anvil_state = plan.upload_files(
                name="anvil-state",
                src=state_file,
                description="Uploading Anvil State",
            )
            service_files[STATE_PATH] = (anvil_state,)
            cmd += " --load-state " + STATE_PATH + "/" + state_file

    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=image,
            ports={
                "rpc": PortSpec(port, application_protocol="http"),
            },
            files=service_files,
            cmd=[cmd],
        ),
    )
