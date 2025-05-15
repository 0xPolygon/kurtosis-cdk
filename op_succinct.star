op_succinct_package = import_module("./lib/op_succinct.star")


def op_succinct_proposer_service_setup(plan, args):
    # FIXME... what is this point of this.. I think we can use a script to do this and we can avoid the weird hard coded chain id
    # echo 'CREATE TABLE `proof_requests` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `type` text NOT NULL, `start_block` integer NOT NULL, `end_block` integer NOT NULL, `status` text NOT NULL, `request_added_time` integer NOT NULL, `prover_request_id` text NULL, `proof_request_time` integer NULL, `last_updated_time` integer NOT NULL, `l1_block_number` integer NULL, `l1_block_hash` text NULL, `proof` blob NULL);'  | sqlite3 foo.db

    op_succinct_proposer_config_template = read_file(
        src="./templates/op-succinct/db/"
        + str(args["zkevm_rollup_chain_id"])
        + "/proofs.db"
    )
    op_succinct_proposer_config_artifact = plan.render_templates(
        name="op-succinct-proposer-config-artifact",
        config={
            "proofs.db": struct(
                template=op_succinct_proposer_config_template, data=args
            )
        },
    )

    # Start the op-succinct-proposer component.
    op_succinct_proposer_configs = (
        op_succinct_package.create_op_succinct_proposer_service_config(
            plan, args, op_succinct_proposer_config_artifact
        )
    )

    plan.add_services(
        configs=op_succinct_proposer_configs,
        description="Starting the op-succinct-proposer component",
    )

    service_name = "op-succinct-proposer" + args["deployment_suffix"]
    
    # Run deploy-op-succinct-contracts.sh script within op-succinct-proposer.
    plan.exec(
        description="Deploying op-succinct contracts",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "mkdir /opt/op-succinct && cp /opt/scripts/deploy-op-succinct-contracts.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                    "/opt/op-succinct/deploy-op-succinct-contracts.sh"
                ),
            ]
        ),
    )

def op_succinct_proposer_run_binary(plan, args):
    service_name = "op-succinct-proposer" + args["deployment_suffix"]

    # # Convert the OP_SUCCINCT_MOCK, AGGLAYER string env variables into boolean.
    # plan.exec(
        # description="Running validity-proposer binary",
    #     service_name=service_name,
    #     recipe=ExecRecipe(
    #         command=[
    #             "/bin/bash",
    #             "-c",
    #             # Log raw values
    #             'echo "Raw OP_SUCCINCT_MOCK=$OP_SUCCINCT_MOCK, AGGLAYER=$AGGLAYER" && ' +
    #             # Enable case-insensitive matching
    #             'shopt -s nocasematch; ' +
    #             # Convert OP_SUCCINCT_MOCK to true/false
    #             'if [[ "$OP_SUCCINCT_MOCK" == "true" ]]; then export OP_SUCCINCT_MOCK=true; else export OP_SUCCINCT_MOCK=false; fi && ' +
    #             # Convert AGGLAYER to true/false
    #             'if [[ "$AGGLAYER" == "true" ]]; then export AGGLAYER=true; else export AGGLAYER=false; fi && ' +
    #             # Log transformed values
    #             'echo "Transformed OP_SUCCINCT_MOCK=$OP_SUCCINCT_MOCK, AGGLAYER=$AGGLAYER" && ' +
    #             # Run validity-proposer and capture output
    #             '/usr/local/bin/validity-proposer 2>&1'
    #         ]
    #     ),
    # )

    # Run the validity-proposer binary.
    plan.exec(
        description="Running validity-proposer binary",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "/usr/local/bin/validity-proposer"
            ]
        ),
    )