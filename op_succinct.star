op_succinct_package = import_module("./lib/op_succinct.star")


def op_succinct_proposer_run(plan, args):
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


def extract_fetch_rollup_config(plan, args):
    # Add a temporary service using the op-succinct-proposer image
    temp_service_name = "temp-op-succinct-proposer"

    service_config = ServiceConfig(
        image=args["op_succinct_proposer_image"],
        cmd=["sleep", "infinity"],  # Keep container running
    )

    plan.add_service(
        name=temp_service_name,
        config=service_config,
        description="Creating temporary service to extract fetch-rollup-config",
    )

    # Copy the binary from the service to the local machine
    plan.store_service_files(
        service_name=temp_service_name,
        src="/usr/local/bin/fetch-rollup-config",
        name="fetch-rollup-config",
        description="Copying fetch-rollup-config binary to files artifact",
    )

    # Remove the temporary service
    plan.remove_service(
        name=temp_service_name,
        description="Removing temporary op-succinct-proposer service",
    )
