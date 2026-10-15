constants = import_module("./constants.star")
input_parser = import_module("./input_parser.star")


def test_validate_sequencer_type(plan):
    for sequencer_type in [
        constants.SEQUENCER_TYPE.cdk_erigon,
        constants.SEQUENCER_TYPE.op_reth,
        constants.SEQUENCER_TYPE.besu,
    ]:
        input_parser.validate_sequencer_type(sequencer_type)

    expect.fails(
        lambda: input_parser.validate_sequencer_type("geth"),
        "Invalid sequencer type",
    )


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
            constants.SEQUENCER_TYPE.op_reth,
            "image:v1.0.0-fork.12",
            0,
            "aggchain",
            None,
        ],
        # besu - a vanilla sovereign chain has no fork id, like the other aggchains. pessimistic is
        # rejected for besu by args_sanity_check, but it proves the zero comes from the sequencer type.
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.besu,
            "image:v1.0.0-fork.12",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.SEQUENCER_TYPE.besu,
            "image:v1.0.0",
            0,
            "aggchain",
            None,
        ],
        [
            constants.CONSENSUS_TYPE.qbft,
            constants.SEQUENCER_TYPE.besu,
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


def test_validate_consensus_type_qbft(plan):
    input_parser.validate_consensus_type(constants.CONSENSUS_TYPE.qbft)
    expect.eq(
        constants.CONSENSUS_TYPE_TO_CONTRACT_MAPPING[constants.CONSENSUS_TYPE.qbft],
        "AggchainQBFT",
    )


def _qbft_args(overrides):
    return (
        input_parser.DEFAULT_ARGS
        | {
            "sequencer_type": constants.SEQUENCER_TYPE.besu,
            "consensus_contract_type": constants.CONSENSUS_TYPE.qbft,
            "besu_validator_count": 4,
            "besu_epoch_length": 20,
        }
        | overrides
    )


def test_args_sanity_check_qbft(plan):
    # Valid: qbft on besu, with the defaults and with a 4-validator chain.
    input_parser.args_sanity_check(plan, {}, _qbft_args({}), {})
    input_parser.args_sanity_check(
        plan, {}, _qbft_args({"besu_validator_count": 1}), {}
    )

    # qbft is Besu only, also on op-reth where other unsupported types fall back to pessimistic.
    for sequencer_type in [
        constants.SEQUENCER_TYPE.op_reth,
        constants.SEQUENCER_TYPE.cdk_erigon,
    ]:
        expect.fails(
            lambda: input_parser.args_sanity_check(
                plan, {}, _qbft_args({"sequencer_type": sequencer_type}), {}
            ),
            "consensus_contract_type 'qbft' requires sequencer_type 'besu'",
        )

    # AggchainQBFT has no multisig signers.
    expect.fails(
        lambda: input_parser.args_sanity_check(
            plan,
            {},
            _qbft_args(
                {
                    "use_agg_sender_validator": True,
                    "agg_sender_validator_total_number": 1,
                    "agg_sender_multisig_threshold": 1,
                }
            ),
            {},
        ),
        "use_agg_sender_validator is not supported",
    )

    # The prover's header fetches must leave room for the other clients of the RPC node.
    expect.fails(
        lambda: input_parser.args_sanity_check(
            plan, {}, _qbft_args({"besu_rpc_max_active_connections": 16}), {}
        ),
        "aggkit_prover_qbft_header_fetch_concurrency",
    )

    expect.fails(
        lambda: input_parser.args_sanity_check(
            plan, {}, _qbft_args({"besu_validator_count": 0}), {}
        ),
        "besu_validator_count",
    )
    expect.fails(
        lambda: input_parser.args_sanity_check(
            plan, {}, _qbft_args({"besu_epoch_length": 0}), {}
        ),
        "besu_epoch_length",
    )
