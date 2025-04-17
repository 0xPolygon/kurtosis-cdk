LOG_LEVEL = [
    "error",
    "warn",
    "info",
    "debug",
    "trace",
]

L1_ENGINES = [
    "geth",
    "anvil",
]

OP_PARAMS = {
    "participant_params": {
        "el_params": [
            "http://op-el-1-op-geth-op-node",
        ],
        "cl_params": [
            "http://op-cl-1-op-node-op-geth",
        ],
    },
}

SUPPORTED_FORK_IDS = [9, 11, 12, 13]

SEQUENCER_TYPES = [
    "erigon",
    "zkevm",
]

DEFAULT_DEPLOYMENT_STAGES = [
    "deploy_l1",
    "deploy_zkevm_contracts_on_l1",
    "deploy_databases",
    "deploy_cdk_central_environment",
    "deploy_cdk_bridge_infra",
    "deploy_cdk_bridge_ui",
    "deploy_agglayer",
    "deploy_cdk_erigon_node",
    "deploy_optimism_rollup",
    "deploy_op_succinct",
    "deploy_l2_contracts",
]

DEFAULT_IMAGES = [
    "aggkit_image",
    "agglayer_image",
    "cdk_erigon_node_image",
    "cdk_node_image",
    "cdk_validium_node_image",
    "zkevm_bridge_proxy_image",
    "zkevm_bridge_service_image",
    "zkevm_bridge_ui_image",
    "zkevm_da_image",
    "zkevm_contracts_image",
    "zkevm_node_image",
    "zkevm_pool_manager_image",
    "zkevm_prover_image",
    "zkevm_sequence_sender_image",
    "anvil_image",
    "mitm_image",
    "op_succinct_contract_deployer_image",
    "op_succinct_server_image",
    "op_succinct_proposer_image",
]

DEFAULT_PORTS = [
    "agglayer_grpc_port",
    "agglayer_readrpc_port",
    "agglayer_prover_port",
    "agglayer_admin_port",
    "agglayer_metrics_port",
    "agglayer_prover_metrics_port",
    "prometheus_port",
    "zkevm_aggregator_port",
    "zkevm_bridge_grpc_port",
    "zkevm_bridge_rpc_port",
    "zkevm_bridge_ui_port",
    "zkevm_bridge_metrics_port",
    "zkevm_dac_port",
    "zkevm_data_streamer_port",
    "zkevm_executor_port",
    "zkevm_hash_db_port",
    "zkevm_pool_manager_port",
    "zkevm_pprof_port",
    "zkevm_rpc_http_port",
    "zkevm_rpc_ws_port",
    "zkevm_cdk_node_port",
    "blockscout_frontend_port",
    "anvil_port",
    "mitm_port",
    "op_succinct_server_port",
    "op_succinct_proposer_port",
]

DEFAULT_STATIC_PORTS = [
    ## L1 static ports (50000-50999).
    "l1_el_start_port",
    "l1_cl_start_port",
    "l1_vc_start_port",
    "l1_additional_services_start_port",
    ## L2 static ports (51000-51999).
    # Agglayer (51000-51099).
    "agglayer_start_port",
    "agglayer_prover_start_port",
    # CDK node (51100-51199).
    "cdk_node_start_port",
    # Bridge services (51200-51299).
    "zkevm_bridge_service_start_port",
    "zkevm_bridge_ui_start_port",
    "reverse_proxy_start_port",
    # Databases (51300-51399).
    "database_start_port",
    "pless_database_start_port",
    # Pool manager (51400-51499).
    "zkevm_pool_manager_start_port",
    # DAC (51500-51599).
    "zkevm_dac_start_port",
    # ZkEVM Provers (51600-51699).
    "zkevm_prover_start_port",
    "zkevm_executor_start_port",
    "zkevm_stateless_executor_start_port",
    # CDK erigon (51700-51799).
    "cdk_erigon_sequencer_start_port",
    "cdk_erigon_rpc_start_port",
    # L2 additional services (52000-52999).
    "arpeggio_start_port",
    "blutgang_start_port",
    "erpc_start_port",
    "panoptichain_start_port",
]

DEFAULT_ACCOUNTS = [
    "zkevm_l2_sequencer_address",
    "zkevm_l2_sequencer_private_key",
    "zkevm_l2_aggregator_address",
    "zkevm_l2_aggregator_private_key",
    "zkevm_l2_claimtxmanager_address",
    "zkevm_l2_claimtxmanager_private_key",
    "zkevm_l2_timelock_address",
    "zkevm_l2_timelock_private_key",
    "zkevm_l2_admin_address",
    "zkevm_l2_admin_private_key",
    "zkevm_l2_loadtest_address",
    "zkevm_l2_loadtest_private_key",
    "zkevm_l2_agglayer_address",
    "zkevm_l2_agglayer_private_key",
    "zkevm_l2_dac_address",
    "zkevm_l2_dac_private_key",
    "zkevm_l2_proofsigner_address",
    "zkevm_l2_proofsigner_private_key",
    "zkevm_l2_l1testing_address",
    "zkevm_l2_l1testing_private_key",
    "zkevm_l2_claimsponsor_address",
    "zkevm_l2_claimsponsor_private_key",
    "zkevm_l2_aggoracle_address",
    "zkevm_l2_aggoracle_private_key",
    "zkevm_l2_sovereignadmin_address",
    "zkevm_l2_sovereignadmin_private_key",
    "zkevm_l2_claimtx_address",
    "zkevm_l2_claimtx_private_key",
]

DEFAULT_L1_ARGS = [
    "l1_engine",
    "l1_chain_id",
    "l1_preallocated_mnemonic",
    "l1_rpc_url",
    "l1_ws_url",
    "l1_beacon_url",
    "l1_additional_services",
    "l1_preset",
    "l1_seconds_per_slot",
    "pectra_enabled",
    "l1_funding_amount",
    "l1_participants_count",
    "l1_deploy_lxly_bridge_and_call",
    "l1_anvil_block_time",
    "l1_anvil_slots_in_epoch",
    "use_previously_deployed_contracts",
    "erigon_datadir_archive",
    "anvil_state_file",
    "mitm_proxied_components",
]

MITM_PROXIED_COMPONENTS = [
    "agglayer",
    "aggkit",
    "bridge",
    "dac",
    "erigon-sequencer",
    "erigon-rpc",
    "cdk-node",
]

DEFAULT_L2_ARGS = [
    "l2_accounts_to_fund",
    "l2_funding_amount",
    "l2_deploy_deterministic_deployment_proxy",
    "l2_deploy_lxly_bridge_and_call",
    "chain_name",
    "sovereign_chain_name",
]

DEFAULT_ROLLUP_ARGS = [
    "zkevm_l2_keystore_password",
    "zkevm_rollup_chain_id",
    "zkevm_rollup_id",
    "zkevm_use_real_verifier",
    "verifier_program_vkey",
    "erigon_strict_mode",
    "gas_token_enabled",
    "gas_token_address",
    "use_dynamic_ports",
    "enable_normalcy",
    "agglayer_prover_sp1_key",
    "agglayer_prover_network_url",
    "agglayer_prover_primary_prover",
    "agglayer_grpc_url",
    "agglayer_readrpc_url",
    "zkevm_path_rw_data",
    "op_el_rpc_url",
    "op_cl_rpc_url",
    "op_succinct_mock",
]

DEFAULT_PLESS_ZKEVM_NODE_ARGS = [
    "trusted_sequencer_node_uri",
    "zkevm_aggregator_host",
    "genesis_file",
    "sovereign_genesis_file",
]

DEFAULT_ADDITIONAL_SERVICES_PARAMS = ["blockscout_params"]

DEFAULT_ARGS = [
    "deployment_suffix",
    "verbosity",
    "global_log_level",
    "sequencer_type",
    "consensus_contract_type",
    "additional_services",
    "polygon_zkevm_explorer",
    "l1_explorer_url",
]


TOTAL_ARGS = (
    DEFAULT_IMAGES
    + DEFAULT_PORTS
    + DEFAULT_STATIC_PORTS
    + DEFAULT_ACCOUNTS
    + DEFAULT_L1_ARGS
    + DEFAULT_L2_ARGS
    + DEFAULT_ROLLUP_ARGS
    + DEFAULT_PLESS_ZKEVM_NODE_ARGS
    + DEFAULT_ADDITIONAL_SERVICES_PARAMS
    + DEFAULT_ARGS
)


def validate_log_level(name, log_level):
    if log_level not in LOG_LEVEL:
        fail(
            "Unsupported {}: '{}', please use one of the accepted params: {}".format(
                name, log_level, LOG_LEVEL
            )
        )


def get_fork_id(zkevm_contracts_image):
    """
    Extract the fork identifier and fork name from a zkevm contracts image name.

    The zkevm contracts tags follow the convention:
    v<SEMVER>-rc.<RC_NUMBER>-fork.<FORK_ID>[-patch.<PATCH_NUMBER>]

    Where:
    - <SEMVER> is the semantic versioning (MAJOR.MINOR.PATCH).
    - <RC_NUMBER> is the release candidate number.
    - <FORK_ID> is the fork identifier.
    - -patch.<PATCH_NUMBER> is optional and represents the patch number.

    Example:
    - v8.0.0-rc.2-fork.12
    - v7.0.0-rc.1-fork.10
    - v7.0.0-rc.1-fork.11-patch.1
    """
    result = zkevm_contracts_image.split("-patch.")[0].split("-fork.")
    if len(result) != 2:
        fail(
            "The zkevm contracts image tag '{}' does not follow the standard v<SEMVER>-rc.<RC_NUMBER>-fork.<FORK_ID>".format(
                zkevm_contracts_image
            )
        )

    fork_id = int(result[1])
    if fork_id not in SUPPORTED_FORK_IDS:
        fail("The fork id '{}' is not supported by Kurtosis CDK".format(fork_id))

    fork_name = "elderberry"
    if fork_id >= 12:
        fork_name = "banana"

    return (fork_id, fork_name)


def input_args_valid_check(plan, args):
    for key in args:
        if key not in TOTAL_ARGS:
            fail("Unsupported parameter: '{}'".format(key))


# Helper function to compact together checks for incompatible parameters in input_parser.star
def args_sanity_check(plan, deployment_stages, args, user_args, op_stack_args):
    input_args_valid_check(plan, args)

    # Fix the op stack el rpc urls according to the deployment_suffix.
    if deployment_stages.get("deploy_optimism_rollup", False):
        if (
            args["op_el_rpc_url"]
            != OP_PARAMS["participant_params"]["el_params"][0]
            + args["deployment_suffix"]
            + ":8545"
        ):
            plan.print(
                "op_el_rpc_url is set to '{}', changing to '{}{}:8545'".format(
                    args["op_el_rpc_url"],
                    OP_PARAMS["participant_params"]["el_params"][0],
                    args["deployment_suffix"],
                )
            )
            args["op_el_rpc_url"] = (
                OP_PARAMS["participant_params"]["el_params"][0]
                + args["deployment_suffix"]
                + ":8545"
            )
        # Fix the op stack cl rpc urls according to the deployment_suffix.
        if (
            args["op_cl_rpc_url"]
            != OP_PARAMS["participant_params"]["cl_params"][0]
            + args["deployment_suffix"]
            + ":8547"
        ):
            plan.print(
                "op_cl_rpc_url is set to '{}', changing to '{}{}:8547'".format(
                    args["op_cl_rpc_url"],
                    OP_PARAMS["participant_params"]["cl_params"][0],
                    args["deployment_suffix"],
                )
            )
            args["op_cl_rpc_url"] = (
                OP_PARAMS["participant_params"]["cl_params"][0]
                + args["deployment_suffix"]
                + ":8547"
            )
        # The optimism-package network_params is a frozen hash table, and is not modifiable during runtime.
        # The check will return fail() instead of dynamically changing the network_params name.
        if op_stack_args["optimism_package"]["chains"][0]["network_params"][
            "name"
        ] != args["deployment_suffix"][1:] and deployment_stages.get(
            "deploy_op_stack", False
        ):
            fail(
                "op_stack_args network_params name is set to '{}', please change it to match deployment_suffix '{}'".format(
                    op_stack_args["optimism_package"]["chains"][0]["network_params"][
                        "name"
                    ],
                    args["deployment_suffix"][1:],
                )
            )

    # Unsupported L1 engine check
    if args["l1_engine"] not in L1_ENGINES:
        fail(
            "Unsupported L1 engine: '{}', please use one of {}".format(
                args["l1_engine"], L1_ENGINES
            )
        )

    if args["sequencer_type"] not in SEQUENCER_TYPES:
        fail(
            "Unsupported sequencer type: '{}', please use one of {}".format(
                args["sequencer_type"], SEQUENCER_TYPES
            )
        )

    # Gas token enabled and gas token address check
    if (
        not args.get("gas_token_enabled", False)
        and args.get("gas_token_address", "0x0000000000000000000000000000000000000000")
        != "0x0000000000000000000000000000000000000000"
    ):
        fail(
            "Gas token address set to '{}' but gas token is not enabled".format(
                args.get("gas_token_address", "")
            )
        )

    # CDK Erigon normalcy and strict mode check
    if args["enable_normalcy"] and args["erigon_strict_mode"]:
        fail("normalcy and strict mode cannot be enabled together")

    # OP rollup deploy_optimistic_rollup and consensus_contract_type check
    if deployment_stages.get("deploy_optimism_rollup", False):
        if args["consensus_contract_type"] != "pessimistic":
            if args["consensus_contract_type"] != "fep":
                plan.print(
                    "Current consensus_contract_type is '{}', changing to pessimistic for OP deployments.".format(
                        args["consensus_contract_type"]
                    )
                )
                # TODO: should this be AggchainFEP instead?
                args["consensus_contract_type"] = "pessimistic"

    # If OP-Succinct is enabled, OP-Rollup must be enabled
    if deployment_stages.get("deploy_op_succinct", False):
        if deployment_stages.get("deploy_optimism_rollup", False) == False:
            fail(
                "OP Succinct requires OP Rollup to be enabled. Change the deploy_optimism_rollup parameter"
            )
        if (
            args["agglayer_prover_sp1_key"] == None
            or args["agglayer_prover_sp1_key"] == ""
        ):
            fail(
                "OP Succinct requires a valid SPN key. Change the agglayer_prover_sp1_key"
            )

    # OP rollup check L1 blocktime >= L2 blocktime
    if deployment_stages.get("deploy_optimism_rollup", False):
        if (
            args.get("l1_seconds_per_slot", 12) < 2
        ):  # 2 seconds is the default blocktime for Optimism L2.
            fail(
                "OP Stack rollup requires L1 blocktime > 1 second. Change the l1_seconds_per_slot parameter"
            )

    # TODO: think about a better way to handle this for future releases
    # TODO: v10+ contracts require deployment of AggLayerGateway which requires programVKey to be non-zero.
    if "v10" in args["zkevm_contracts_image"]:
        if args["consensus_contract_type"] == "fep":
            if (
                args["program_vkey"]
                != "0x0000000000000000000000000000000000000000000000000000000000000000"
            ):
                plan.print(
                    "Current programVKey is {}. AggchainFEP consensus requires programVKey === bytes32(0). Overwriting to equal bytes32(0)".format(
                        args["program_vkey"]
                    )
                )
                args[
                    "program_vkey"
                ] = "0x0000000000000000000000000000000000000000000000000000000000000000"
            if args["fork_id"] != 0:
                plan.print(
                    "Current fork_id is {}. AggchainFEP consensus requires fork_id == 0. Overwriting to equal 0".format(
                        args["fork_id"]
                    )
                )
                args["fork_id"] = 0

        # v10+ contracts support pessimistic consensus - we will need to overwrite the zero program_vkey with non-zero verifier_program_vkey value.
        if args["consensus_contract_type"] == "pessimistic":
            if (
                args["program_vkey"]
                == "0x0000000000000000000000000000000000000000000000000000000000000000"
            ):
                plan.print(
                    "Current programVKey is {}. Pessimistic consensus VKey should take the value from verifier_program_vkey: {}. Overwriting programVKey with verifier_program_vkey.".format(
                        args["program_vkey"], args["verifier_program_vkey"]
                    )
                )
                args["program_vkey"] = args["verifier_program_vkey"]
