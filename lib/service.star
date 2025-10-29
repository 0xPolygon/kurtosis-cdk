data_availability_package = import_module("./data_availability.star")
constants = import_module("../src/package_io/constants.star")


def get_contract_setup_addresses(plan, args, deployment_stages):
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
    if deployment_stages.get("deploy_optimism_rollup", False):
        extract["agglayer_gateway_address"] = "fromjson | .aggLayerGatewayAddress"

    if data_availability_package.is_cdk_validium(args):
        extract[
            "polygon_data_committee_address"
        ] = "fromjson | .polygonDataCommitteeAddress"

    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat {}/combined.json".format(constants.OUTPUT_DIR)],
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
    service = plan.get_service(name=args["l2_rpc_name"] + args["deployment_suffix"])

    # Get L2 rpc http url.
    http_url = ""
    if "rpc" in service.ports:
        http_url = "http://{}:{}".format(
            service.ip_address, service.ports["rpc"].number
        )
    else:
        plan.print("No rpc port found for service: '{}'".format(service.name))

    # Get L2 rpc ws url.
    ws_url = ""
    if "ws-rpc" in service.ports:
        ws_url = "ws://{}:{}".format(service.ip_address, service.ports["ws-rpc"].number)
    elif "ws" in service.ports:
        ws_url = "ws://{}:{}".format(service.ip_address, service.ports["ws"].number)
    else:
        plan.print("No ws rpc port found for service: '{}'".format(service.name))

    return struct(http=http_url, ws=ws_url)


# Return the HTTP RPC URL of the sequencer or empty if it doesn't exist.
def get_sequencer_rpc_url(plan, args):
    if args.get("consensus_contract_type") not in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
    ]:
        return ""

    sequencer_service = plan.get_service(
        args["sequencer_name"] + args["deployment_suffix"]
    )
    sequencer_rpc_url = "http://{}:{}".format(
        sequencer_service.ip_address, sequencer_service.ports["rpc"].number
    )

    return sequencer_rpc_url


def get_sovereign_contract_setup_addresses(plan, args):
    extract = {
        "sovereign_ger_proxy_addr": "fromjson | .ger_proxy_addr",
        "sovereign_bridge_proxy_addr": "fromjson | .bridge_proxy_addr",
        "sovereign_rollup_addr": "fromjson | .sovereignRollupContract",
        "zkevm_rollup_chain_id": "fromjson | .rollupChainID",
    }

    exec_recipe = ExecRecipe(
        command=[
            "/bin/sh",
            "-c",
            "cat {}/sovereign-rollup-out.json".format(constants.CONTRACTS_DIR),
        ],
        extract=extract,
    )
    service_name = "contracts" + args["deployment_suffix"]
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
        "op_succinct_agg_proof_mode": "fromjson | .AGG_PROOF_MODE",
        "op_succinct_agglayer": "fromjson | .AGGLAYER",
        "op_succinct_mock": "fromjson | .OP_SUCCINCT_MOCK",
        "sp1_challenger": "fromjson | .challenger",
        "sp1_finalization_period": "fromjson | .finalizationPeriod",
        "sp1_l2_block_time": "fromjson | .l2BlockTime",
        "sp1_owner": "fromjson | .owner",
        "sp1_proposer": "fromjson | .proposer",
        "sp1_proxy_admin": "fromjson | .proxyAdmin",
        "sp1_submission_interval": "fromjson | .submissionInterval",
        "submission_interval": "fromjson | .SUBMISSION_INTERVAL",
        # "l2oo_address": "fromjson | .L2OO_ADDRESS",
        # "mock_verifier_address": "fromjson | .VERIFIER_ADDRESS",
        # "sp1_aggregation_vkey": "fromjson | .aggregationVkey",
        # "sp1_l2_output_oracle_impl": "fromjson | .opSuccinctL2OutputOracleImpl",
        # "sp1_range_vkey_commitment": "fromjson | .rangeVkeyCommitment",
        # "sp1_rollup_config_hash": "fromjson | .rollupConfigHash",
        # "sp1_starting_block_number": "fromjson | .startingBlockNumber",
        # "sp1_starting_output_root": "fromjson | .startingOutputRoot",
        # "sp1_starting_timestamp": "fromjson | .startingTimestamp",
        # "sp1_verifier": "fromjson | .verifier",
        # "sp1_verifier_address": "fromjson | .SP1_VERIFIER_PLONK",
        # "sp1_verifier_gateway_address": "fromjson | .SP1_VERIFIER_GATEWAY_PLONK",
    }

    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat /opt/op-succinct/op-succinct-env-vars.json"],
        extract=extract,
    )
    service_name = "contracts" + args["deployment_suffix"]
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


def get_op_succinct_l2oo_config(plan, args):
    extract = {
        "sp1_challenger": "fromjson | .challenger",
        "sp1_finalization_period": "fromjson | .finalizationPeriod",
        "sp1_l2_block_time": "fromjson | .l2BlockTime",
        "sp1_l2_output_oracle_impl": "fromjson | .opSuccinctL2OutputOracleImpl",
        "sp1_owner": "fromjson | .owner",
        "sp1_proposer": "fromjson | .proposer",
        "sp1_rollup_config_hash": "fromjson | .rollupConfigHash",
        "sp1_starting_block_number": "fromjson | .startingBlockNumber",
        "sp1_starting_output_root": "fromjson | .startingOutputRoot",
        "sp1_starting_timestamp": "fromjson | .startingTimestamp",
        "sp1_submission_interval": "fromjson | .submissionInterval",
        "sp1_verifier": "fromjson | .verifier",
        "sp1_aggregation_vkey": "fromjson | .aggregationVkey",
        "sp1_range_vkey_commitment": "fromjson | .rangeVkeyCommitment",
        "sp1_proxy_admin": "fromjson | .proxyAdmin",
    }

    exec_recipe = ExecRecipe(
        command=[
            "/bin/sh",
            "-c",
            "cat /opt/op-succinct/opsuccinctl2ooconfig.json",
        ],
        extract=extract,
    )
    service_name = "contracts" + args["deployment_suffix"]
    result = plan.exec(
        description="Reading the opsuccinctl2ooconfig JSON file from {} service".format(
            service_name
        ),
        service_name=service_name,
        recipe=exec_recipe,
    )
    return get_exec_recipe_result(result)


def get_kurtosis_addresses(args):
    l2_sequencer_address = args["l2_sequencer_address"]
    l2_aggregator_address = args["l2_aggregator_address"]
    l2_timelock_address = args["l2_timelock_address"]
    l2_admin_address = args["l2_admin_address"]
    l2_dac_address = args["l2_dac_address"]
    l2_aggoracle_address = args["l2_aggoracle_address"]
    l2_sovereignadmin_address = args["l2_sovereignadmin_address"]

    return {
        "l2_sequencer_address": l2_sequencer_address,
        "l2_aggregator_address": l2_aggregator_address,
        "l2_timelock_address": l2_timelock_address,
        "l2_admin_address": l2_admin_address,
        "l2_dac_address": l2_dac_address,
        "l2_aggoracle_address": l2_aggoracle_address,
        "l2_sovereignadmin_address": l2_sovereignadmin_address,
    }


# Get aggOracleCommittee contract address after deployment on L2.
def get_aggoracle_committee_address(plan, args):
    extract = {
        "agg_oracle_committee_address": "fromjson | .aggOracleCommitteeProxyAddress"
    }

    exec_recipe = ExecRecipe(
        command=["/bin/sh", "-c", "cat {}/combined.json".format(constants.OUTPUT_DIR)],
        extract=extract,
    )

    service_name = "contracts"
    if args["deploy_agglayer"]:
        plan.print("Changing querying service name to helper")
        if "zkevm_rollup_manager_address" in args:
            service_name = "helper"
    service_name += args["deployment_suffix"]
    result = plan.exec(
        description="Getting agg_oracle_committee_address from {} service".format(
            service_name
        ),
        service_name=service_name,
        recipe=exec_recipe,
    )
    return get_exec_recipe_result(result)
