ger_validator_signer = import_module("./ger_validator_signer.star")


def test_service_name_and_url(plan):
    args = {"deployment_suffix": "-001", "ger_validator_signer_port": 8080}
    expect.eq(ger_validator_signer.service_name(args, 1), "ger-validator-001-001")
    expect.eq(ger_validator_signer.service_name(args, 3), "ger-validator-001-003")
    # Always 3 digits, also from the 10th validator on (up to 255)
    expect.eq(ger_validator_signer.service_name(args, 10), "ger-validator-001-010")
    expect.eq(ger_validator_signer.service_name(args, 255), "ger-validator-001-255")
    expect.eq(ger_validator_signer.url(args, 2), "http://ger-validator-001-002:8080")

    args = {"deployment_suffix": "-002", "ger_validator_signer_port": 9000}
    expect.eq(ger_validator_signer.url(args, 1), "http://ger-validator-002-001:9000")


def test_urls(plan):
    # The URLs that contracts.sh registers in the AggOracleCommittee: the ones of the services, in order
    args = {
        "deployment_suffix": "-001",
        "ger_validator_signer_port": 8080,
        "agg_oracle_committee_total_validators": 3,
    }
    expect.eq(
        ger_validator_signer.urls(args),
        [
            "http://ger-validator-001-001:8080",
            "http://ger-validator-001-002:8080",
            "http://ger-validator-001-003:8080",
        ],
    )
