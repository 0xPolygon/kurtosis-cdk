constants = import_module("./constants.star")
input_parser = import_module("./input_parser.star")


# S15 (dev-ui-ci-snapshot plan): regression tests for the anvil-L2 input-parser
# branches added in S3/S4/S4b/S5 (args_sanity_check's "Anvil L2 checks" V1/V2/
# V4/V5/V6, and the op_el_rpc_url/op_cl_rpc_url aliasing). These call the real
# parse_args() entrypoint end to end (not a hand-rolled partial args dict) so
# they exercise exactly what a real params YAML would trigger, and so they
# stay correct if parse_args's internal wiring changes.
#
# _MINIMAL_ANVIL_USER_ARGS is the smallest valid anvil args block:
# l1_engine/sequencer_type/consensus_contract_type and nothing else. It
# deliberately does NOT spell out l1_rpc_url/l1_ws_url/l1_beacon_url -- S17
# fixed set_l1_client_args to skip an anvil L1 rather than clobbering those
# URLs back to the ethereum-package service names, and
# test_parse_args_anvil_l1_urls_not_clobbered below is the regression net for
# that fix.
def _minimal_anvil_user_args():
    return {
        "args": {
            "l1_engine": "anvil",
            "sequencer_type": constants.SEQUENCER_TYPE.anvil,
            "consensus_contract_type": constants.CONSENSUS_TYPE.ecdsa_multisig,
        },
    }


def _with_args(user_args, extra_args):
    merged = dict(user_args)
    merged["args"] = dict(user_args.get("args", {})) | extra_args
    return merged


def _with_stages(user_args, extra_stages):
    merged = dict(user_args)
    merged["deployment_stages"] = (
        dict(user_args.get("deployment_stages", {})) | extra_stages
    )
    return merged


def test_parse_args_anvil_happy_path(plan):
    # Sanity baseline: the minimal valid anvil args block must parse cleanly,
    # so every failure test below is actually exercising ONE broken field, not
    # tripping over a bad fixture.
    (deployment_stages, args, op_args) = input_parser.parse_args(
        plan, _minimal_anvil_user_args()
    )
    expect.eq(args["sequencer_type"], constants.SEQUENCER_TYPE.anvil)
    expect.eq(args["consensus_contract_type"], constants.CONSENSUS_TYPE.ecdsa_multisig)


def test_parse_args_anvil_requires_ecdsa_multisig(plan):
    # V1: sequencer_type 'anvil' must fail loudly (not silently coerce, unlike
    # the op-reth branch) for every OTHER consensus_contract_type, since
    # pessimistic/rollup/cdk-validium/fep all break L2->L1 exit settlement on
    # the anvil L2 (aggsender's multisig-committee query reverts).
    for bad_consensus in [
        constants.CONSENSUS_TYPE.pessimistic,
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
        constants.CONSENSUS_TYPE.fep,
    ]:
        user_args = _with_args(
            _minimal_anvil_user_args(), {"consensus_contract_type": bad_consensus}
        )
        expect.fails(
            lambda ua=user_args: input_parser.parse_args(plan, ua),
            "requires consensus_contract_type 'ecdsa-multisig'",
        )


def test_parse_args_anvil_rejects_optimism_package(plan):
    # V4: sequencer_type 'anvil' never deploys the optimism-package -- an
    # args file that supplies one anyway (e.g. copy-pasted from an op-reth
    # params file) must fail fast instead of silently ignoring the block.
    user_args = dict(_minimal_anvil_user_args())
    user_args["optimism_package"] = {"chains": {"001": {}}}
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "does not use the optimism-package",
    )


def test_parse_args_anvil_rejects_nonpositive_block_time_or_slots(plan):
    # V5: --block-time 0 disables interval mining and --slots-in-an-epoch 0 is
    # nonsense -- both must be rejected, individually.
    for bad_field in ["l2_anvil_block_time", "l2_anvil_slots_in_epoch"]:
        user_args = _with_args(_minimal_anvil_user_args(), {bad_field: 0})
        expect.fails(
            lambda ua=user_args: input_parser.parse_args(plan, ua),
            "must be >= 1",
        )


def test_parse_args_anvil_requires_mnemonic(plan):
    # V6: the mnemonic is both the chain's prefund source and the L2 funder;
    # an empty one must be rejected rather than producing an unfundable chain.
    user_args = _with_args(_minimal_anvil_user_args(), {"l2_anvil_mnemonic": ""})
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "l2_anvil_mnemonic must not be empty",
    )


def test_parse_args_anvil_deployment_stage_coupling(plan):
    # V2: the anvil L2 node is launched inside the deploy_agglayer_contracts_on_l1
    # stage (main.star), because initialize_rollup needs a live L2. Disabling
    # that stage while deploy_cdk_central_environment stays on (the default)
    # would wire aggkit to a service that is never created -- must fail fast.
    user_args = _with_stages(
        _minimal_anvil_user_args(), {"deploy_agglayer_contracts_on_l1": False}
    )
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "it cannot be skipped while deploy_cdk_central_environment is enabled",
    )

    # Regression: disabling BOTH stages together (a legitimate "skip the whole
    # rollup-creation flow" configuration, e.g. re-attaching to a pre-deployed
    # chain) must NOT trip V2.
    user_args_both_off = _with_stages(
        _minimal_anvil_user_args(),
        {
            "deploy_agglayer_contracts_on_l1": False,
            "deploy_cdk_central_environment": False,
        },
    )
    input_parser.parse_args(plan, user_args_both_off)


def test_parse_args_anvil_op_el_rpc_url_aliasing(plan):
    # sequencer_type 'anvil' reuses the op-stack URL keys (op_el_rpc_url /
    # op_cl_rpc_url) rather than introducing new ones, aliasing them to the
    # anvil L2 service so aggkit/agglayer/contracts.sh keep working unchanged.
    # The alias must win regardless of what the user supplied (including the
    # op-reth default), and must respect deployment_suffix.
    for user_supplied_url, deployment_suffix, expected in [
        (None, "-001", "http://l2-anvil-001:8545"),
        (
            "http://op-el-1-op-reth-op-node-001:8545",  # the op-reth default
            "-001",
            "http://l2-anvil-001:8545",
        ),
        ("http://something-wrong:8545", "-002", "http://l2-anvil-002:8545"),
    ]:
        extra = {"deployment_suffix": deployment_suffix}
        if user_supplied_url:
            extra["op_el_rpc_url"] = user_supplied_url
            extra["op_cl_rpc_url"] = user_supplied_url
        user_args = _with_args(_minimal_anvil_user_args(), extra)
        (_, args, _) = input_parser.parse_args(plan, user_args)
        expect.eq(args["op_el_rpc_url"], expected)
        expect.eq(args["op_cl_rpc_url"], expected)


def test_parse_args_op_reth_op_el_rpc_url_aliasing_unaffected_by_anvil(plan):
    # Regression net: the anvil aliasing branch must be sequencer_type-gated.
    # op-reth's own (pre-existing) op_el_rpc_url/op_cl_rpc_url aliasing to
    # op-el-1-op-reth-op-node* / op-cl-1-op-node-op-reth* must be completely
    # unaffected by the new anvil branch.
    user_args = {
        "args": {
            "sequencer_type": constants.SEQUENCER_TYPE.op_reth,
            "consensus_contract_type": constants.CONSENSUS_TYPE.pessimistic,
            "deployment_suffix": "-001",
            "op_el_rpc_url": "http://something-wrong:8545",
        },
    }
    (_, args, _) = input_parser.parse_args(plan, user_args)
    expect.eq(args["op_el_rpc_url"], "http://op-el-1-op-reth-op-node-001:8545")
    expect.eq(args["op_cl_rpc_url"], "http://op-cl-1-op-node-op-reth-001:8547")


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


# S17 (adversarial review): three regression nets for fixes made during the
# review pass.


def test_parse_args_anvil_l1_urls_not_clobbered(plan):
    # set_anvil_args() points the three L1 URLs at the anvil service, and
    # set_l1_client_args() used to run straight afterwards and overwrite all
    # three with `http://el-1-<el>-<cl>:8545`-style names that an anvil L1
    # never creates -- so every consumer retried forever against a nonexistent
    # host. Every anvil params file carried an explicit three-line workaround
    # for this. Assert the derived values survive.
    (deployment_stages, args, op_args) = input_parser.parse_args(
        plan, _minimal_anvil_user_args()
    )
    expect.eq(args["l1_rpc_url"], "http://anvil-001:8545")
    expect.eq(args["l1_ws_url"], "ws://anvil-001:8545")
    expect.eq(args["l1_beacon_url"], "http://anvil-001:8545")


def test_parse_args_l1_client_args_still_apply_without_anvil(plan):
    # The other half of the same fix: for a NON-anvil L1, set_l1_client_args
    # must keep deriving the ethereum-package service names exactly as before.
    (deployment_stages, args, op_args) = input_parser.parse_args(
        plan,
        {
            "args": {
                "sequencer_type": constants.SEQUENCER_TYPE.cdk_erigon,
                "l1_el_type": "geth",
                "l1_cl_type": "lighthouse",
            },
        },
    )
    expect.eq(args["l1_rpc_url"], "http://el-1-geth-lighthouse:8545")
    expect.eq(args["l1_ws_url"], "ws://el-1-geth-lighthouse:8546")
    expect.eq(args["l1_beacon_url"], "http://cl-1-lighthouse-geth:4000")


def test_parse_args_anvil_l1_rejects_op_reth(plan):
    # An anvil L1 cannot host an op-reth L2: the optimism-package's op-node
    # launcher requires an `el_cl_genesis_data` artifact that only the
    # ethereum-package L1 produces, so the run dies at Starlark validation time
    # with an error that names the artifact and nothing else. Fail with a
    # message that names the real cause instead.
    expect.fails(
        lambda: input_parser.parse_args(
            plan,
            {
                "args": {
                    "l1_engine": "anvil",
                    "sequencer_type": constants.SEQUENCER_TYPE.op_reth,
                },
            },
        ),
        "cannot be combined with sequencer_type 'op-reth'",
    )


def test_parse_args_anvil_rejects_custom_mnemonic(plan):
    # V7: contracts.sh's initialize_rollup hard-codes the default anvil dev
    # mnemonic when funding sovereignadmin/aggoracle/claimsponsor on the L2, so
    # a custom l2_anvil_mnemonic leaves that funder with a zero balance and the
    # three `cast send` calls fail deep inside the contracts service.
    user_args = _with_args(
        _minimal_anvil_user_args(),
        {
            "l2_anvil_mnemonic": "custom custom custom custom custom custom custom custom custom custom custom custom"
        },
    )
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "must currently stay at the default anvil dev mnemonic",
    )


# K3 (snapshot-v2-aggkit-e2e plan): regression tests for agglayer_settle_
# confirmations / agglayer_settlement_policy, the two new settlement knobs
# added when the dead [outbound.rpc.settle] block was migrated to
# [settlement.pessimistic-proof-tx-config] (see static_files/agglayer/
# config.toml). These call parse_args() end to end, same as the anvil tests
# above, so a revert of K3's validation (or of the defaults themselves) trips
# a test here rather than silently restoring the old 12-confirmation
# upstream default. Reuses _minimal_anvil_user_args() purely as "the smallest
# valid args block" -- these two knobs are not anvil-specific.


def test_parse_args_agglayer_settle_confirmations_default(plan):
    (_, args, _) = input_parser.parse_args(plan, _minimal_anvil_user_args())
    expect.eq(args["agglayer_settle_confirmations"], 1)


def test_parse_args_agglayer_settle_confirmations_override(plan):
    user_args = _with_args(
        _minimal_anvil_user_args(), {"agglayer_settle_confirmations": 5}
    )
    (_, args, _) = input_parser.parse_args(plan, user_args)
    expect.eq(args["agglayer_settle_confirmations"], 5)


def test_parse_args_agglayer_settle_confirmations_rejects_below_one(plan):
    # agglayer_settle_confirmations must be >= 1 -- 0 and negative values are
    # nonsense (agglayer would need to wait for a receipt to appear before it
    # exists).
    for bad_value in [0, -1]:
        user_args = _with_args(
            _minimal_anvil_user_args(), {"agglayer_settle_confirmations": bad_value}
        )
        expect.fails(
            lambda ua=user_args: input_parser.parse_args(plan, ua),
            "agglayer_settle_confirmations must be >= 1",
        )


def test_parse_args_agglayer_settlement_policy_default(plan):
    (_, args, _) = input_parser.parse_args(plan, _minimal_anvil_user_args())
    expect.eq(args["agglayer_settlement_policy"], "safe")


def test_parse_args_agglayer_settlement_policy_override(plan):
    for value in ["latest", "safe", "finalized"]:
        user_args = _with_args(
            _minimal_anvil_user_args(), {"agglayer_settlement_policy": value}
        )
        (_, args, _) = input_parser.parse_args(plan, user_args)
        expect.eq(args["agglayer_settlement_policy"], value)


def test_parse_args_agglayer_settlement_policy_rejects_invalid(plan):
    user_args = _with_args(
        _minimal_anvil_user_args(), {"agglayer_settlement_policy": "bogus"}
    )
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "Unsupported agglayer_settlement_policy",
    )
