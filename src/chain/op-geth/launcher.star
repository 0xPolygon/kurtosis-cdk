aggkit_package = import_module("../shared/aggkit.star")
aggkit_prover = import_module("./aggkit_prover.star")
constants = import_module("../../package_io/constants.star")
op_succinct_proposer = import_module("./op_succinct_proposer.star")
ports_package = import_module("../shared/ports.star")
zkevm_bridge_service = import_module("../shared/zkevm_bridge_service.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
):
    consensus_type = args.get("consensus_contract_type")
    if consensus_type == constants.CONSENSUS_TYPE.fep:
        # Retrieve L1 genesis and rename it to <l1_chain_id>.json for op-succinct-proposer
        l1_genesis_artifact = plan.get_files_artifact(name="el_cl_genesis_data")
        new_genesis_name = "{}.json".format(args.get("l1_chain_id"))
        result = plan.run_sh(
            name="rename-l1-genesis",
            description="Rename L1 genesis",
            files={"/tmp": l1_genesis_artifact},
            run="mv /tmp/genesis.json /tmp/{}".format(new_genesis_name),
            store=[
                StoreSpec(
                    src="/tmp/{}".format(new_genesis_name),
                    name="el_cl_genesis_data_for_op_succinct",
                )
            ],
        )
        artifact_count = len(result.files_artifacts)
        if artifact_count != 1:
            fail(
                "The service should have generated 1 artifact, got {}.".format(
                    artifact_count
                )
            )

        # op-succinct-proposer
        op_succinct_proposer.run(plan, args | contract_setup_addresses)

        # aggkit-prover
        aggkit_prover.run(
            plan, args, contract_setup_addresses, sovereign_contract_setup_addresses
        )

    # zkevm-bridge-service (legacy)
    l2_rpc_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    zkevm_bridge_service.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        l2_rpc_url,
    )

    aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
    )

    return struct(
        rpc_url=None,
        bridge_service_url=None,
    )
