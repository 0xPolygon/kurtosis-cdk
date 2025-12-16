STATE_PATH = "/tmp"


def run(plan, args):
    chain_id = str(args["l1_chain_id"])
    block_time = args.get("l1_anvil_block_time")
    slots_in_epoch = args.get("l1_anvil_slots_in_epoch")
    service_files = {}
    mnemonic = args.get("l1_preallocated_mnemonic")

    cmd = (
        "anvil --block-time "
        + str(block_time)
        + " --slots-in-an-epoch "
        + str(slots_in_epoch)
        + " --chain-id "
        + chain_id
        + " --host 0.0.0.0 --port "
        + str(args["anvil_port"])
        + " --dump-state "
        + STATE_PATH
        + "/state_out.json"
        + " --balance 1000000000"
        + ' --mnemonic "'
        + mnemonic
        + '"'
    )

    load_state = bool(args.get("anvil_state_file"))

    if load_state:
        anvil_state = plan.upload_files(
            name="anvil-state",
            src=args["anvil_state_file"],
            description="Uploading Anvil State",
        )
        service_files = {
            STATE_PATH: anvil_state,
        }
        cmd += " --load-state " + STATE_PATH + "/" + args["anvil_state_file"]

    plan.add_service(
        name="anvil" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["anvil_image"],
            ports={
                "rpc": PortSpec(args["anvil_port"], application_protocol="http"),
            },
            files=service_files,
            cmd=[cmd],
        ),
    )
