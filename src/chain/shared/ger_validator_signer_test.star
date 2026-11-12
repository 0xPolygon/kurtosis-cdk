ger_validator_signer = import_module("./ger_validator_signer.star")


def test_service_name_and_url(plan):
    # contracts.sh registers these URLs in the AggOracleCommittee, building them as
    # "http://ger-validator<deployment_suffix>-00<index>:<port>": the name of the service has to be the same
    args = {"deployment_suffix": "-001", "ger_validator_signer_port": 8080}
    expect.eq(ger_validator_signer.service_name(args, 1), "ger-validator-001-001")
    expect.eq(ger_validator_signer.service_name(args, 3), "ger-validator-001-003")
    expect.eq(ger_validator_signer.url(args, 2), "http://ger-validator-001-002:8080")

    args = {"deployment_suffix": "-002", "ger_validator_signer_port": 9000}
    expect.eq(ger_validator_signer.url(args, 1), "http://ger-validator-002-001:9000")
