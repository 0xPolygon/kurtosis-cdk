constants = import_module("../package_io/constants.star")

AGGLOGGER_IMAGE = (
    "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglogger:bf1f8c1"
)

OP_CONFIG_TEMPLATE = "op-config.json"
ZKEVM_CONFIG_TEMPLATE = "zkevm-config.json"


def run(
    plan,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    l1_context,
    l2_context,
    agglayer_context,
):
    # Determine config template based on sequencer type
    agglogger_config_file = ""
    if l2_context.sequencer_type == constants.SEQUENCER_TYPE.op_geth:
        agglogger_config_file = OP_CONFIG_TEMPLATE
    elif l2_context.sequencer_type == constants.SEQUENCER_TYPE.cdk_erigon:
        agglogger_config_file = ZKEVM_CONFIG_TEMPLATE
    else:
        fail("Unsupported sequencer type: {}".format(l2_context.sequencer_type))

    agglogger_config_artifact = plan.render_templates(
        name="agglogger-config" + l2_context.name,
        config={
            "config.json": struct(
                template=read_file(
                    src="../../static_files/additional_services/agglogger/{}".format(
                        agglogger_config_file
                    ),
                ),
                data={
                    # l1
                    "l1_rpc_url": l1_context.rpc_url,
                    "l1_chain_id": l1_context.chain_id,
                    # l2
                    "l2_rpc_url": l2_context.rpc_http_url,
                    "l2_chain_id": l2_context.chain_id,
                    "l2_network_id": l2_context.network_id,
                    # agglayer
                    "agglayer_rpc_url": agglayer_context.rpc_url,
                    # contract addresses
                    "rollup_manager_address": contract_setup_addresses.get(
                        "rollup_manager_address"
                    ),
                    "l1_bridge_address": contract_setup_addresses.get(
                        "l1_bridge_address"
                    ),
                    "l1_ger_address": contract_setup_addresses.get("l1_ger_address"),
                    "l2_ger_address": contract_setup_addresses.get("l2_ger_address"),
                    "sovereign_ger_proxy_addr": sovereign_contract_setup_addresses.get(
                        "sovereign_ger_proxy_addr"
                    ),
                },
            ),
        },
    )

    plan.add_service(
        name="agglogger" + l2_context.name,
        config=ServiceConfig(
            image=AGGLOGGER_IMAGE,
            files={
                "/etc/agglogger": Directory(artifact_names=[agglogger_config_artifact]),
            },
            entrypoint=["sh", "-c"],
            cmd=["./agglogger run --config /etc/agglogger/config.json", "2>&1"],
        ),
    )
