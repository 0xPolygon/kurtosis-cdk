op_succinct_package = import_module("./lib/op_succinct.star")


def op_succinct_proposer_run(plan, args):
    # FIXME... what is this point of this.. I think we can use a script to do this and we can avoid the weird hard coded chain id
    # echo 'CREATE TABLE `proof_requests` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `type` text NOT NULL, `start_block` integer NOT NULL, `end_block` integer NOT NULL, `status` text NOT NULL, `request_added_time` integer NOT NULL, `prover_request_id` text NULL, `proof_request_time` integer NULL, `last_updated_time` integer NOT NULL, `l1_block_number` integer NULL, `l1_block_hash` text NULL, `proof` blob NULL);'  | sqlite3 foo.db

    # Extract L1 genesis file
    l1_genesis_original_artifact = plan.get_files_artifact(name="el_cl_genesis_data")
    new_genesis_name = "{}.json".format(args.get("l1_chain_id"))
    result = plan.run_sh(
        name="rename-l1-genesis-for-op-succinct",
        description="Rename L1 genesis",
        files={"/tmp": Directory(artifact_names=[l1_genesis_original_artifact])},
        run="mv /tmp/genesis.json /tmp/{}".format(new_genesis_name),
        store=[
            "/tmp/{}".format(new_genesis_name),
        ],
    )
    artifact_count = len(result.files_artifacts)
    if artifact_count != 1:
        fail(
            "The service should have generated 1 artifact, got {}.".format(
                artifact_count
            )
        )
    l1_genesis_artifact = result.files_artifacts[0]

    # Start the op-succinct-proposer component.
    op_succinct_proposer_configs = (
        op_succinct_package.create_op_succinct_proposer_service_config(
            args, l1_genesis_artifact
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

    plan.run_sh(
        # File name was fetch-rollup-config, changed to fetch-l2oo-config at some point
        run="[ -e /usr/local/bin/fetch-rollup-config ] && cp -f /usr/local/bin/fetch-rollup-config /usr/local/bin/fetch-l2oo-config; echo 'copying fetch-l2oo-config binary to files artifact...'",
        image=args.get("op_succinct_proposer_image"),
        store=[
            StoreSpec(
                src="/usr/local/bin/fetch-l2oo-config",
                name="fetch-l2oo-config",
            )
        ],
        wait=None,
        description="Extract fetch-l2oo-config from the op-succinct-proposer image to files artifact",
    )


def create_evm_sketch_genesis(plan, args):
    parse_evm_sketch_genesis_artifact = plan.render_templates(
        name="parse-evm-sketch-genesis.sh",
        config={
            "parse-evm-sketch-genesis.sh": struct(
                template=read_file(
                    src="./templates/op-succinct/parse-evm-sketch-genesis.sh"
                ),
                data=args,
            ),
        },
        description="Create parse-evm-sketch-genesis.sh files artifact",
    )

    op_geth_genesis = plan.store_service_files(
        service_name="op-el-1-op-geth-op-node" + args["deployment_suffix"],
        name="op_geth_genesis.json",
        src="/network-configs/genesis-" + str(args["zkevm_rollup_chain_id"]) + ".json",
        description="Storing OP Geth genesis.json for evm-sketch-genesis field in aggkit-prover.",
    )

    # Add a temporary service using the contracts image
    temp_service_name = "temp-contracts"

    files = {}
    files["/opt/op-succinct/"] = Directory(artifact_names=[op_geth_genesis])

    files["/opt/scripts/"] = Directory(
        artifact_names=[parse_evm_sketch_genesis_artifact]
    )

    # Create helper service to deploy contracts
    plan.add_service(
        name=temp_service_name,
        config=ServiceConfig(
            image=args["agglayer_contracts_image"],
            files=files,
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )

    # Parse .config section of L1 geth genesis for evm-sketch-genesis input
    plan.exec(
        description="Parsing .config section of L1 geth genesis for evm-sketch-genesis input",
        service_name="temp-contracts",
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "cp /opt/scripts/parse-evm-sketch-genesis.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                    "/opt/op-succinct/parse-evm-sketch-genesis.sh"
                ),
            ]
        ),
    )
