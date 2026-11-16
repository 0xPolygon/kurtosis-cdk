constants = import_module("../../package_io/constants.star")


def service_name(args, index):
    """Name of the service of the GER validator number `index`, that starts at 1: ger-validator<suffix>-001, ..."""
    number = str(index)
    return "ger-validator{}-{}{}".format(
        args["deployment_suffix"], "0" * (3 - len(number)), number
    )


def url(args, index):
    """URL of the REST API of the GER validator number `index`, inside the enclave."""
    return "http://{}:{}".format(
        service_name(args, index), args["ger_validator_signer_port"]
    )


def urls(args):
    """URLs of all the GER validators, in order (validator 1 first).

    They are the only source of the URLs that the AggOracleCommittee registers at the genesis of the L2: contracts.sh
    (create_predeployed_op_genesis) gets them in the template value ger_validator_urls.
    """
    return [
        url(args, index)
        for index in range(1, args["agg_oracle_committee_total_validators"] + 1)
    ]


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
