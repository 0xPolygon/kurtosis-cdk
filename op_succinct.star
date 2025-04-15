op_succinct_package = import_module("./lib/op_succinct.star")


def op_succinct_contract_deployer_run(plan, args):
    # Start the op-succinct contract deployer helper component.
    op_succinct_contract_deployer_configs = (
        op_succinct_package.create_op_succinct_contract_deployer_service_config(
            plan, args
        )
    )

    plan.add_services(
        configs=op_succinct_contract_deployer_configs,
        description="Starting the op-succinct contract deployer helper component",
    )

    service_name = "op-succinct-contract-deployer" + args["deployment_suffix"]
    plan.exec(
        description="Deploying op-succinct contracts",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "cp /opt/scripts/deploy-op-succinct-contracts.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                    "/opt/op-succinct/deploy-op-succinct-contracts.sh"
                ),
            ]
        ),
    )


def op_succinct_server_run(plan, args, op_succinct_env_vars):
    # Start the op-succinct-server component.
    op_succinct_server_configs = (
        op_succinct_package.create_op_succinct_server_service_config(
            args, op_succinct_env_vars
        )
    )

    plan.add_services(
        configs=op_succinct_server_configs,
        description="Starting the op-succinct-server component",
    )


def op_succinct_proposer_run(plan, args, op_succinct_env_vars):
    # FIXME... what is this point of this.. I think we can use a script to do this and we can avoid the weird hard coded chain id
    # echo 'CREATE TABLE `proof_requests` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `type` text NOT NULL, `start_block` integer NOT NULL, `end_block` integer NOT NULL, `status` text NOT NULL, `request_added_time` integer NOT NULL, `prover_request_id` text NULL, `proof_request_time` integer NULL, `last_updated_time` integer NOT NULL, `l1_block_number` integer NULL, `l1_block_hash` text NULL, `proof` blob NULL);'  | sqlite3 foo.db

    op_succinct_proposer_config_template = read_file(
        src="./templates/op-succinct/db/2151908/proofs.db"
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
            args, op_succinct_env_vars, op_succinct_proposer_config_artifact
        )
    )

    plan.add_services(
        configs=op_succinct_proposer_configs,
        description="Starting the op-succinct-proposer component",
    )


def sp1_verifier_contracts_deployer_run(plan, args):
    service_name = "op-succinct-contract-deployer" + args["deployment_suffix"]
    plan.exec(
        description="Deploying SP1 Verifier Contracts for OP Succinct",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "cp /opt/scripts/deploy-sp1-verifier-contracts.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                    "/opt/op-succinct/deploy-sp1-verifier-contracts.sh"
                ),
            ]
        ),
    )


def op_succinct_l2oo_deployer_run(plan, args):
    service_name = "op-succinct-contract-deployer" + args["deployment_suffix"]
    plan.exec(
        description="Deploying L2OO Contract",
        service_name=service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "cp /opt/scripts/deploy-l2oo.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                    "/opt/op-succinct/deploy-l2oo.sh"
                ),
            ]
        ),
    )
