op_succinct_package = import_module("./lib/op_succinct.star")

def op_succinct_contract_deployer_run(plan, args):
    # Start the op-succinct contract deployer helper component.
    op_succinct_contract_deployer_configs = op_succinct_package.create_op_succinct_contract_deployer_service_config(
        plan, args
    )

    plan.add_services(
        configs=op_succinct_contract_deployer_configs,
        description="Starting the op-succinct contract deployer helper component",
    )

    plan.exec(
        description="Deploying op-succinct contracts",
        service_name="op-succinct-contract-deployer" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "cp /opt/scripts/deploy-op-succinct-contracts.sh /opt/op-succinct/ && chmod +x {0} && ./{0}".format(
                    "/opt/op-succinct/deploy-op-succinct-contracts.sh"
                ),
            ]
        ),
    )

def op_succinct_server_run(plan, args):
    # Start the op-succinct-server component.
    op_succinct_server_configs = op_succinct_package.create_op_succinct_server_service_config(
        args
    )

    plan.add_services(
        configs=op_succinct_server_configs,
        description="Starting the op-succinct-server component",
    )

def op_succinct_proposer_run(plan, args):
    # Create the op-succinct config.
    op_succinct_proposer_config_template = read_file(
        src="./templates/op-succinct/db/2151908/proofs.db"
    )
    op_succinct_proposer_config_artifact = plan.render_templates(
        name="op-succinct-proposer-config-artifact",
        config={
            "proofs.db": struct(
                template=op_succinct_proposer_config_template,
                data=args
            )
        },
    )

    # Start the op-succinct-proposer component.
    op_succinct_proposer_configs = op_succinct_package.create_op_succinct_proposer_service_config(
        args, op_succinct_proposer_config_artifact
    )

    plan.add_services(
        configs=op_succinct_proposer_configs,
        description="Starting the op-succinct-proposer component",
    )