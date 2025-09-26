input_parser = import_module("./input_parser.star")


def test_get_fork_id(plan):
    tests = [
        # rollup - supported forks
        ["rollup", "agglayer-contracts:v1.0.0-fork.13", 13, "banana", None],
        ["rollup", "agglayer-contracts:v1.0.0-fork.12", 12, "banana", None],
        ["rollup", "agglayer-contracts:v1.0.0-fork.11", 11, "elderberry", None],
        ["rollup", "agglayer-contracts:v1.0.0-fork.9", 9, "elderberry", None],
        # rollup - unsupported forks should fail
        [
            "rollup",
            "agglayer-contracts:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            "rollup",
            "agglayer-contracts:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # rollup - no fork specified should fail
        ["rollup", "agglayer-contracts:v1.0.0", 0, "", "does not follow the standard"],
        # cdk validium - supported forks
        ["cdk_validium", "agglayer-contracts:v1.0.0-fork.13", 13, "banana", None],
        ["cdk_validium", "agglayer-contracts:v1.0.0-fork.12", 12, "banana", None],
        ["cdk_validium", "agglayer-contracts:v1.0.0-fork.11", 11, "elderberry", None],
        ["cdk_validium", "agglayer-contracts:v1.0.0-fork.9", 9, "elderberry", None],
        # cdk validium - unsupported forks should fail
        [
            "cdk_validium",
            "agglayer-contracts:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            "cdk_validium",
            "agglayer-contracts:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # cdk validium - no fork specified should fail
        [
            "cdk_validium",
            "agglayer-contracts:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # pessimistic - supported forks
        ["pessimistic", "agglayer-contracts:v1.0.0-fork.13", 13, "banana", None],
        ["pessimistic", "agglayer-contracts:v1.0.0-fork.12", 12, "banana", None],
        ["pessimistic", "agglayer-contracts:v1.0.0-fork.11", 11, "elderberry", None],
        ["pessimistic", "agglayer-contracts:v1.0.0-fork.9", 9, "elderberry", None],
        # pessimistic - unsupported forks should fail
        [
            "pessimistic",
            "agglayer-contracts:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            "pessimistic",
            "agglayer-contracts:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # cdk pessimistic - no fork specified should fail
        [
            "pessimistic",
            "agglayer-contracts:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # ecdsa multisig
        ["ecdsa_multisig", "agglayer-contracts:v1.0.0-fork.13", 0, "aggchain", None],
        ["ecdsa_multisig", "agglayer-contracts:v1.0.0-fork.12", 0, "aggchain", None],
        ["ecdsa_multisig", "agglayer-contracts:v1.0.0-fork.11", 0, "aggchain", None],
        ["ecdsa_multisig", "agglayer-contracts:v1.0.0", 0, "aggchain", None],
        # fep
        ["fep", "agglayer-contracts:v1.0.0-fork.13", 0, "aggchain", None],
        ["fep", "agglayer-contracts:v1.0.0-fork.12", 0, "aggchain", None],
        ["fep", "agglayer-contracts:v1.0.0-fork.11", 0, "aggchain", None],
        ["fep", "agglayer-contracts:v1.0.0", 0, "aggchain", None],
    ]

    for i, t in enumerate(tests):
        [contract_type, image, expected_fork_id, expected_fork_name, expected_error] = (
            t[0],
            t[1],
            t[2],
            t[3],
            t[4],
        )
        if expected_error:
            expect.fails(
                lambda: input_parser.get_fork_id(contract_type, image),
                expected_error,
            )
        else:
            (fork_id, fork_name) = input_parser.get_fork_id(contract_type, image)
            expect.eq(fork_id, expected_fork_id)
            expect.eq(fork_name, expected_fork_name)
