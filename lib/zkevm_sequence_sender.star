data_availability_package = import_module("./data_availability.star")


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
            "config.toml": struct(
                data=args
                | {
                    "zkevm_is_validium": data_availability_package.is_cdk_validium(
                        args
                    ),
                },
                template=sequence_sender_config_template,
            ),
        },
    )
    sequence_sender_service_config = ServiceConfig(
        image=args["zkevm_sequence_sender_image"],
        files={
            "/etc/zkevm": Directory(
                artifact_names=[
                    genesis_artifact,
                    sequencer_keystore_artifact,
                    sequence_sender_config_artifact,
                ]
            )
        },
        cmd=[
            "/bin/sh",
            "-c",
            "/app/zkevm-seqsender run --network custom --custom-network-file /etc/zkevm/genesis.json --cfg /etc/zkevm/config.toml",
        ],
    )

    return {sequence_sender_name: sequence_sender_service_config}
