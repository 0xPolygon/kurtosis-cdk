constants = import_module("./src/package_io/constants.star")
input_parser = import_module("./input_parser.star")


def test_get_fork_id(plan):
    tests = [
        # rollup - supported forks
        [
            constants.CONSENSUS_TYPE.rollup,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.13",
            13,
            "banana",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.rollup,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.12",
            12,
            "banana",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.rollup,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.11",
            11,
            "elderberry",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.rollup,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.9",
            9,
            "elderberry",
            None,
        ],
        # rollup - unsupported forks should fail
        [
            constants.CONSENSUS_TYPE.rollup,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            constants.CONSENSUS_TYPE.rollup,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # rollup - no fork specified should fail
        [
            constants.CONSENSUS_TYPE.rollup,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # cdk validium - supported forks
        [
            constants.CONSENSUS_TYPE.cdk_validium,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.13",
            13,
            "banana",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.cdk_validium,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.12",
            12,
            "banana",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.cdk_validium,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.11",
            11,
            "elderberry",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.cdk_validium,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.9",
            9,
            "elderberry",
            None,
        ],
        # cdk validium - unsupported forks should fail
        [
            constants.CONSENSUS_TYPE.cdk_validium,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            constants.CONSENSUS_TYPE.cdk_validium,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # cdk validium - no fork specified should fail
        [
            constants.CONSENSUS_TYPE.cdk_validium,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # pessimistic - supported forks
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.13",
            13,
            "banana",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.12",
            12,
            "banana",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.11",
            11,
            "elderberry",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.9",
            9,
            "elderberry",
            None,
        ],
        # pessimistic - unsupported forks should fail
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.8",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.14",
            0,
            "",
            "not supported by Kurtosis CDK",
        ],
        # cdk pessimistic - no fork specified should fail
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0",
            0,
            "",
            "does not follow the standard",
        ],
        # ecdsa multisig
        [
            constants.CONSENSUS_TYPE.ecdsa_multisig,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.13",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.ecdsa_multisig,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.12",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.ecdsa_multisig,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.11",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.ecdsa_multisig,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0",
            0,
            "aggchain",
            None,
        ],
        # fep
        [
            constants.CONSENSUS_TYPE.fep,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.13",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.fep,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.12",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.fep,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.11",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.fep,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0",
            0,
            "aggchain",
            None,
        ],
        # optimism rollup
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.op_geth,
            "image:v1.0.0-fork.12",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.cdk_erigon,
            "image:v1.0.0-fork.12",
            12,
            "banana",
            None,
        ],
    ]

    for i, t in enumerate(tests):
        [
            contract_type,
            sequencer_type,
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
                lambda: input_parser.get_fork_id(contract_type, sequencer_type, image),
                expected_error,
            )
        else:
            (fork_id, fork_name) = input_parser.get_fork_id(
                contract_type, sequencer_type, image
            )
            expect.eq(fork_id, expected_fork_id)
            expect.eq(fork_name, expected_fork_name)
