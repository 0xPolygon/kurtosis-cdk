def get_contract_setup_addresses(plan, args):
    if "zkevm_rollup_manager_address" in args:
        get_rollup_info_artifact = plan.get_files_artifact(
            name="get-rollup-info-artifact",
        )
        result = plan.run_sh(
            description="Retrieving rollup info",
            image=args["toolbox_image"],
            run="chmod +x {0} && sh {0} {1} {2} {3}".format(
                "/opt/zkevm/get-rollup-info.sh",
                args["l1_rpc_url"],
                args["zkevm_rollup_manager_address"],
                args["zkevm_rollup_chain_id"],
            ),
            files={"/opt/zkevm": get_rollup_info_artifact},
        )

        plan.print(result)
        plan.print(result.output)
        plan.print(
            json.decode(
                '{"zkevm_bridge_address": "0x1Fe038B54aeBf558638CA51C91bC8cCa06609e91"}'
            )
        )
        contract_addresses = json.decode(result.output)
        plan.print(contract_addresses)
        return contract_addresses

    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat /opt/zkevm/combined.json"],
        extract={
            "zkevm_bridge_address": "fromjson | .polygonZkEVMBridgeAddress",
            "zkevm_rollup_address": "fromjson | .rollupAddress",
            "zkevm_rollup_manager_address": "fromjson | .polygonRollupManagerAddress",
            "zkevm_rollup_manager_block_number": "fromjson | .deploymentRollupManagerBlockNumber",
            "zkevm_global_exit_root_address": "fromjson | .polygonZkEVMGlobalExitRootAddress",
            "zkevm_global_exit_root_l2_address": "fromjson | .polygonZkEVMGlobalExitRootL2Address",
            "polygon_data_committee_address": "fromjson | .polygonDataCommitteeAddress",
            "pol_token_address": "fromjson | .polTokenAddress",
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
