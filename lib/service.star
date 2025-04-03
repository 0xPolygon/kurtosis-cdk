data_availability_package = import_module("./data_availability.star")


def get_contract_setup_addresses(plan, args, deployment_stages):
    if deployment_stages.get("deploy_optimism_rollup", False):
        # Deploying optimism rollup doesn't have .rollupAddress field. This should be removed.
        extract = {
            "zkevm_bridge_address": "fromjson | .polygonZkEVMBridgeAddress",
            "zkevm_bridge_l2_address": "fromjson | .polygonZkEVML2BridgeAddress",
            "zkevm_rollup_manager_address": "fromjson | .polygonRollupManagerAddress",
            "zkevm_rollup_manager_block_number": "fromjson | .deploymentRollupManagerBlockNumber",
            "zkevm_global_exit_root_address": "fromjson | .polygonZkEVMGlobalExitRootAddress",
            "zkevm_global_exit_root_l2_address": "fromjson | .polygonZkEVMGlobalExitRootL2Address",
            "pol_token_address": "fromjson | .polTokenAddress",
            "zkevm_admin_address": "fromjson | .admin",
        }
    else:
        extract = {
            "zkevm_bridge_address": "fromjson | .polygonZkEVMBridgeAddress",
            "zkevm_bridge_l2_address": "fromjson | .polygonZkEVML2BridgeAddress",
            "zkevm_rollup_address": "fromjson | .rollupAddress",
            "zkevm_rollup_manager_address": "fromjson | .polygonRollupManagerAddress",
            "zkevm_rollup_manager_block_number": "fromjson | .deploymentRollupManagerBlockNumber",
            "zkevm_global_exit_root_address": "fromjson | .polygonZkEVMGlobalExitRootAddress",
            "zkevm_global_exit_root_l2_address": "fromjson | .polygonZkEVMGlobalExitRootL2Address",
            "pol_token_address": "fromjson | .polTokenAddress",
            "zkevm_admin_address": "fromjson | .admin",
        }
    if data_availability_package.is_cdk_validium(args):
        extract[
            "polygon_data_committee_address"
        ] = "fromjson | .polygonDataCommitteeAddress"

    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat /opt/zkevm/combined.json"],
        extract=extract,
    )
    service_name = "contracts"
    if args["deploy_agglayer"]:
        plan.print("Changing querying service name to helper")
        if "zkevm_rollup_manager_address" in args:
            service_name = "helper"
    service_name += args["deployment_suffix"]
    result = plan.exec(
        description="Getting contract setup addresses from {} service".format(
            service_name
        ),
        service_name=service_name,
        recipe=exec_recipe,
    )
    return get_exec_recipe_result(result)


# Get result from an exec recipe and remove the extract prefix added to the keys.
def get_exec_recipe_result(result):
    key_prefix = "extract."
    result_dict = {}
    for key, value in result.items():
        if key.startswith(key_prefix):
            new_key = key[len(key_prefix) :]
            result_dict[new_key] = value
    return result_dict


# Return the HTTP and WS URLs of the L2 RPC service.
def get_l2_rpc_url(plan, args):
    l2_rpc_service = plan.get_service(
        name=args["l2_rpc_name"] + args["deployment_suffix"]
    )
    return struct(
        http="http://{}:{}".format(
            l2_rpc_service.name,
            l2_rpc_service.ports["rpc"].number,
        ),
        ws="ws://{}:{}".format(
            l2_rpc_service.name,
            l2_rpc_service.ports["ws-rpc"].number,
        ),
    )


def get_sovereign_contract_setup_addresses(plan, args):
    extract = {
        "sovereign_ger_proxy_addr": "fromjson | .ger_proxy_addr",
        "sovereign_bridge_proxy_addr": "fromjson | .bridge_proxy_addr",
        "sovereign_rollup_addr": "fromjson | .sovereignRollupContract",
        "zkevm_rollup_chain_id": "fromjson | .rollupChainID",
    }

    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat /opt/zkevm-contracts/sovereign-rollup-out.json"],
        extract=extract,
    )
    service_name = "contracts"
    service_name += args["deployment_suffix"]
    result = plan.exec(
        description="Getting contract setup addresses from {} service".format(
            service_name
        ),
        service_name=service_name,
        recipe=exec_recipe,
    )
    return get_exec_recipe_result(result)


def get_op_succinct_env_vars(plan, args):
    extract = {
        "submission_interval": "fromjson | .SUBMISSION_INTERVAL",
        "verifier_address": "fromjson | .VERIFIER_ADDRESS",
        "l2oo_address": "fromjson | .L2OO_ADDRESS",
        "op_succinct_mock": "fromjson | .OP_SUCCINCT_MOCK",
        "op_succinct_agglayer": "fromjson | .OP_SUCCINCT_AGGLAYER",
        "l1_preallocated_mnemonic": "fromjson | .PRIVATE_KEY",
    }

    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat /opt/op-succinct/op-succinct-env-vars.json"],
        extract=extract,
    )
    service_name = "op-succinct-contract-deployer" + args["deployment_suffix"]
    result = plan.exec(
        description="Getting op-succinct environment variables from {} service".format(
            service_name
        ),
        service_name=service_name,
        recipe=exec_recipe,
    )
    return get_exec_recipe_result(result)


def get_l1_op_contract_addresses(plan, args, op_deployer_configs_artifact):
    proposer_address = _read_l1_op_contract_address(
        plan, op_deployer_configs_artifact, "proposer", args["zkevm_rollup_chain_id"]
    )
    batcher_address = _read_l1_op_contract_address(
        plan, op_deployer_configs_artifact, "batcher", args["zkevm_rollup_chain_id"]
    )
    sequencer_address = _read_l1_op_contract_address(
        plan, op_deployer_configs_artifact, "sequencer", args["zkevm_rollup_chain_id"]
    )
    challenger_address = _read_l1_op_contract_address(
        plan, op_deployer_configs_artifact, "challenger", args["zkevm_rollup_chain_id"]
    )
    proxy_admin_address = _read_l1_op_contract_address(
        plan,
        op_deployer_configs_artifact,
        "l1ProxyAdmin",
        args["zkevm_rollup_chain_id"],
    )
    return {
        "op_proposer_address": proposer_address,
        "op_batcher_address": batcher_address,
        "op_sequencer_address": sequencer_address,
        "op_challenger_address": challenger_address,
        "op_proxy_admin_address": proxy_admin_address,
    }


def _read_l1_op_contract_address(plan, op_deployer_configs_artifact, key, chain_id):
    result = plan.run_sh(
        description="Reading op-{} contract address".format(key),
        files={
            "/opt/config": op_deployer_configs_artifact,
        },
        run="jq --raw-output '.address' /opt/config/{}-{}.json | tr -d '\n'".format(
            key, chain_id
        ),
    )
    return result.output
