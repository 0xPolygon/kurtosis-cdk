constants = import_module("../../package_io/constants.star")


def service_name(args, index):
    """Name of the service of the GER validator number `index`, that starts at 1.

    The AggOracleCommittee registers the URL of this service at the genesis of the L2, in create_predeployed_op_genesis of
    contracts.sh, that builds the name in the same way: keep both in sync.
    """
    return "ger-validator{}-00{}".format(args["deployment_suffix"], index)


def url(args, index):
    """URL of the REST API of the GER validator number `index`, inside the enclave."""
    return "http://{}:{}".format(
        service_name(args, index), args["ger_validator_signer_port"]
    )


def run(plan, args, contract_setup_addresses):
    """Deploy the GER validators of the AggOracleCommittee v2, if it is enabled."""
    if not args.get("use_agg_oracle_committee_v2", False):
        return

    plan.print("Deploying the GER validators")
    config_template = read_file(
        src="../../../static_files/chain/shared/ger-validator-signer/config.toml"
    )
    # The validators are numbered from 1, as the keystores that contracts.sh creates
    for index in range(1, args["agg_oracle_committee_total_validators"] + 1):
        _deploy_validator(plan, args, contract_setup_addresses, config_template, index)


def _deploy_validator(plan, args, contract_setup_addresses, config_template, index):
    """Deploy the GER validator number `index`, with its own configuration and keystore."""
    config_artifact = plan.render_templates(
        name="ger-validator-config-{}{}".format(index, args["deployment_suffix"]),
        config={
            "config.toml": struct(
                template=config_template,
                data=args | contract_setup_addresses | {"ger_validator_index": index},
            )
        },
    )

    keystore_artifact = plan.store_service_files(
        name="ger-validator-{}-keystore{}".format(index, args["deployment_suffix"]),
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/gervalidator-{}.keystore".format(index),
    )

    plan.add_service(
        name=service_name(args, index),
        config=ServiceConfig(
            image=args["ger_validator_signer_image"],
            ports={
                "rest": PortSpec(
                    args["ger_validator_signer_port"],
                    application_protocol="http",
                ),
            },
            files={
                "/etc/ger_validator_signer": Directory(
                    artifact_names=[config_artifact, keystore_artifact],
                ),
            },
            cmd=["run", "--cfg", "/etc/ger_validator_signer/config.toml"],
        ),
    )
