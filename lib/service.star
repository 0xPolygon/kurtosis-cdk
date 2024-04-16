def get_contract_setup_addresses(plan, args):
    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat /opt/zkevm/combined.json"],
        extract={
            "zkevm_bridge_address": "fromjson | .polygonZkEVMBridgeAddress",
            "zkevm_rollup_address": "fromjson | .rollupAddress",
            "zkevm_rollup_manager_address": "fromjson | .polygonRollupManagerAddress",
            "zkevm_global_exit_root_address": "fromjson | .polygonZkEVMGlobalExitRootAddress",
            "zkevm_global_exit_root_l2_address": "fromjson | .polygonZkEVMGlobalExitRootL2Address",
            "polygon_data_committee_address": "fromjson | .polygonDataCommitteeAddress",
            "pol_token_address": "fromjson | .polTokenAddress",
            "rollup_manager_block_number": "fromjson | .deploymentRollupManagerBlockNumber",
        },
    )
    result = plan.exec(
        description="Getting contract setup addresses",
        service_name="contracts" + args["deployment_suffix"],
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
