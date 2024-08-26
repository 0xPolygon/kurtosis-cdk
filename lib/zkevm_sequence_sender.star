data_availability_package = import_module("./data_availability.star")


def create_zkevm_sequence_sender_config(
    args,
    sequence_sender_config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
):
    sequence_sender_name = "zkevm-node-sequence-sender" + args["deployment_suffix"]
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
            "/app/zkevm-seqsender run --network custom --custom-network-file /etc/zkevm/genesis.json --cfg /etc/zkevm/sequence-sender-config.toml",
        ],
    )

    return {sequence_sender_name: sequence_sender_service_config}
