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


# Helper function to compact together checks for incompatible parameters in input_parser.star
def args_sanity_check(plan, deployment_stages, args, user_args, op_stack_args):
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

    # Check if zkevm_contracts_image contains v10 in its tag. Then check if the consensus_contract_type is pessimistic.
    # v10+ contracts do not support the deployment of contracts on non-pessimistic consensus after introduction of AgglayerGateway.
    # TODO: think about a better way to handle this for future releases
    if "v10" in args["zkevm_contracts_image"]:
        if (
            args["consensus_contract_type"] == "cdk-validium"
            or args["consensus_contract_type"] == "rollup"
        ):
            plan.print(
                'Current consensus_contract_type is {}. Overwriting consensus_contract_type to "pessimistic" for v10+ contracts, because it is the only supported consensus.'.format(
                    args["consensus_contract_type"]
                )
            )
            # TODO: should this be AggchainFEP instead?
            args["consensus_contract_type"] = "pessimistic"

        # TODO: Add these additional checks once the contracts are updated to v10
        # TODO: v10+ contracts require deployment of AggLayerGateway which requires programVKey to be non-zero.
        # if args["consensus_contract_type"] == "fep":
        #     if (
        #         args["program_vkey"]
        #         != "0x0000000000000000000000000000000000000000000000000000000000000000"
        #     ):
        #         plan.print(
        #             "Current programVKey is {}. AggchainFEP consensus requires programVKey === bytes32(0). Overwriting to equal bytes32(0)".format(
        #                 args["program_vkey"]
        #             )
        #         )
        #         args[
        #             "program_vkey"
        #         ] = "0x0000000000000000000000000000000000000000000000000000000000000000"
        #     if args["fork_id"] != 0:
        #         plan.print(
        #             "Current fork_id is {}. AggchainFEP consensus requires fork_id == 0. Overwriting to equal 0".format(
        #                 args["fork_id"]
        #             )
        #         )
        #         args["fork_id"] = 0

        # # v10+ contracts support pessimistic consensus - we will need to overwrite the zero program_vkey with non-zero verifier_program_vkey value.
        # if args["consensus_contract_type"] == "pessimistic":
        #     if (
        #         args["program_vkey"]
        #         == "0x0000000000000000000000000000000000000000000000000000000000000000"
        #     ):
        #         plan.print(
        #             "Current programVKey is {}. Pessimistic consensus VKey should take the value from verifier_program_vkey: {}. Overwriting programVKey with verifier_program_vkey.".format(
        #                 args["program_vkey"], args["verifier_program_vkey"]
        #             )
        #         )
        #         args["program_vkey"] = args["verifier_program_vkey"]
