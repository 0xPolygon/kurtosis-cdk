input_parser = import_module("./input_parser.star")


def test_get_fork_id(plan):
    tests = [
        # rollup - supported forks
        ["rollup", False, "image:v1.0.0-fork.13", 13, "banana", None],
        ["rollup", False, "image:v1.0.0-fork.12", 12, "banana", None],
        ["rollup", False, "image:v1.0.0-fork.11", 11, "elderberry", None],
        ["rollup", False, "image:v1.0.0-fork.9", 9, "elderberry", None],
        # rollup - unsupported forks should fail
        [
            "rollup",
            False,
            "image:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            "rollup",
            False,
            "image:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # rollup - no fork specified should fail
        [
            "rollup",
            False,
            "image:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # cdk validium - supported forks
        [
            "cdk_validium",
            False,
            "image:v1.0.0-fork.13",
            13,
            "banana",
            None,
        ],
        [
            "cdk_validium",
            False,
            "image:v1.0.0-fork.12",
            12,
            "banana",
            None,
        ],
        [
            "cdk_validium",
            False,
            "image:v1.0.0-fork.11",
            11,
            "elderberry",
            None,
        ],
        [
            "cdk_validium",
            False,
            "image:v1.0.0-fork.9",
            9,
            "elderberry",
            None,
        ],
        # cdk validium - unsupported forks should fail
        [
            "cdk_validium",
            False,
            "image:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            "cdk_validium",
            False,
            "image:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # cdk validium - no fork specified should fail
        [
            "cdk_validium",
            False,
            "image:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # pessimistic - supported forks
        ["pessimistic", False, "image:v1.0.0-fork.13", 13, "banana", None],
        ["pessimistic", False, "image:v1.0.0-fork.12", 12, "banana", None],
        [
            "pessimistic",
            False,
            "image:v1.0.0-fork.11",
            11,
            "elderberry",
            None,
        ],
        [
            "pessimistic",
            False,
            "image:v1.0.0-fork.9",
            9,
            "elderberry",
            None,
        ],
        # pessimistic - unsupported forks should fail
        [
            "pessimistic",
            False,
            "image:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            "pessimistic",
            False,
            "image:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # cdk pessimistic - no fork specified should fail
        [
            "pessimistic",
            False,
            "image:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # ecdsa multisig
        [
            "ecdsa_multisig",
            False,
            "image:v1.0.0-fork.13",
            0,
            "aggchain",
            None,
        ],
        [
            "ecdsa_multisig",
            False,
            "image:v1.0.0-fork.12",
            0,
            "aggchain",
            None,
        ],
        [
            "ecdsa_multisig",
            False,
            "image:v1.0.0-fork.11",
            0,
            "aggchain",
            None,
        ],
        ["ecdsa_multisig", False, "image:v1.0.0", 0, "aggchain", None],
        # fep
        ["fep", False, "image:v1.0.0-fork.13", 0, "aggchain", None],
        ["fep", False, "image:v1.0.0-fork.12", 0, "aggchain", None],
        ["fep", False, "image:v1.0.0-fork.11", 0, "aggchain", None],
        ["fep", False, "image:v1.0.0", 0, "aggchain", None],
        # optimism rollup
        ["pessimistic", True, "image:v1.0.0-fork.12", 0, "aggchain", None],
        ["pessimistic", False, "image:v1.0.0-fork.12", 12, "banana", None],
    ]

    for i, t in enumerate(tests):
        [
            contract_type,
            deploy_optimism_rollup,
            image,
            expected_fork_id,
            expected_fork_name,
            expected_error,
        ] = (
            t[0],
            t[1],
            t[2],
            t[3],
            t[4],
            t[5],
        )
        if expected_error:
            expect.fails(
                lambda: input_parser.get_fork_id(
                    contract_type, deploy_optimism_rollup, image
                ),
                expected_error,
            )
        else:
            (fork_id, fork_name) = input_parser.get_fork_id(
                contract_type, deploy_optimism_rollup, image
            )
            expect.eq(fork_id, expected_fork_id)
            expect.eq(fork_name, expected_fork_name)
