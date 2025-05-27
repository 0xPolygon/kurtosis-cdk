op_succinct_package = import_module("./lib/op_succinct.star")


def op_succinct_proposer_run(plan, args):
    # FIXME... what is this point of this.. I think we can use a script to do this and we can avoid the weird hard coded chain id
    # echo 'CREATE TABLE `proof_requests` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `type` text NOT NULL, `start_block` integer NOT NULL, `end_block` integer NOT NULL, `status` text NOT NULL, `request_added_time` integer NOT NULL, `prover_request_id` text NULL, `proof_request_time` integer NULL, `last_updated_time` integer NOT NULL, `l1_block_number` integer NULL, `l1_block_hash` text NULL, `proof` blob NULL);'  | sqlite3 foo.db

    # Start the op-succinct-proposer component.
    op_succinct_proposer_configs = (
        op_succinct_package.create_op_succinct_proposer_service_config(args)
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

    plan.run_sh(
        run="echo copying fetch-rollup-config binary to files artifact...",
        image=args["op_succinct_proposer_image"],
        store=[
            StoreSpec(
                src="/usr/local/bin/fetch-rollup-config",
                name="fetch-rollup-config",
            )
        ],
        wait=None,
        description="Extract fetch-rollup-config from the op-succinct-proposer image to files artifact",
    )
