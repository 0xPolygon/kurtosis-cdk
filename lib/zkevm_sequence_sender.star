data_availability_package = import_module("./data_availability.star")


def create_zkevm_sequence_sender_config(
    args,
    sequence_sender_config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
):
    zkevm_sequence_sender_name = "zkevm-sequence-sender" + args["deployment_suffix"]
    zkevm_sequence_sender_service_config = ServiceConfig(
        image=args["zkevm_sequence_sender_image"],
        files={
            "/etc/zkevm": Directory(
                artifact_names=[
                    sequence_sender_config_artifact,
                    genesis_artifact,
                    sequencer_keystore_artifact,
                ]
            )
        },
        cmd=[
            "/bin/sh",
            "-c",
            "/app/zkevm-seqsender run --network custom --custom-network-file /etc/zkevm/genesis.json --cfg /etc/zkevm/zkevm-sequence-sender-config.toml",
        ],
    )
    return {zkevm_sequence_sender_name: zkevm_sequence_sender_service_config}
