
def create_zkevm_sequence_sender_config(
    plan, args, genesis_artifact, sequencer_keystore_artifact
):
    sequence_sender_name = "zkevm-node-sequence-sender" + args["deployment_suffix"]
    sequence_sender_config_template = read_file(
        src="../templates/trusted-node/sequence-sender-config.toml"
    )
    sequence_sender_config_artifact = plan.render_templates(
        name="zkevm-sequence-sender-config-artifact",
        config={
            "config.yaml": struct(
                data=args,
                template=sequence_sender_config_template,
            ),
        },
    )
    sequence_sender_service_config = ServiceConfig(
        image=args["zkevm_sequence_sender_image"],
        files={
            "/etc/zkevm": Directory(
                    artifact_names=[genesis_artifact, sequencer_keystore_artifact, sequence_sender_config_artifact]
            )
        },
        cmd=["/bin/sh", "-c",
            "/app/zkevm-seqsender run --network custom --custom-network-file /etc/zkevm/genesis.json --cfg /etc/zkevm/config.toml --components sequence-sender"],
        # entrypoint=["sh", "-c"],
        # cmd=["sleep infinity"]
    )

    return {sequence_sender_name: sequence_sender_service_config}
