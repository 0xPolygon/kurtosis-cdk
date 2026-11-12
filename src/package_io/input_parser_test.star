constants = import_module("./constants.star")
input_parser = import_module("./input_parser.star")


# Tests for the anvil L2 input-parser branches (args_sanity_check's anvil checks
# and the op_el_rpc_url/op_cl_rpc_url aliasing). They call parse_args() end to end
# so that they exercise what a params file triggers.
#
# _minimal_anvil_user_args is the smallest valid anvil args block. It does not set
# the L1 URLs: test_parse_args_anvil_l1_urls_not_clobbered covers their derivation.
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
    # The L1 anvil must boot with a block gas limit high enough for the 60M
    # bridge-implementation deploy override (contracts.sh Amsterdam patch).
    expect.true(args["l1_anvil_gas_limit"] >= 60000000)


def test_parse_args_anvil_requires_ecdsa_multisig(plan):
    # Every other consensus type breaks L2->L1 exit settlement on the anvil L2, so
    # it fails instead of being coerced.
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
    # An optimism_package block, e.g. copied from an op-reth params file, must fail
    # instead of being ignored.
    user_args = dict(_minimal_anvil_user_args())
    user_args["optimism_package"] = {"chains": {"001": {}}}
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "does not use the optimism-package",
    )


def test_parse_args_anvil_rejects_nonpositive_block_time_or_slots(plan):
    # A zero block time disables interval mining; both values must be >= 1.
    for bad_field in ["l2_anvil_block_time", "l2_anvil_slots_in_epoch"]:
        user_args = _with_args(_minimal_anvil_user_args(), {bad_field: 0})
        expect.fails(
            lambda ua=user_args: input_parser.parse_args(plan, ua),
            "must be >= 1",
        )


def test_parse_args_anvil_deployment_stage_coupling(plan):
    # The anvil L2 is launched inside the deploy_agglayer_contracts_on_l1 stage, so
    # skipping it while deploy_cdk_central_environment is on must fail.
    user_args = _with_stages(
        _minimal_anvil_user_args(), {"deploy_agglayer_contracts_on_l1": False}
    )
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "it cannot be skipped while deploy_cdk_central_environment is enabled",
    )

    # Disabling both stages together is a valid configuration.
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


def test_parse_args_anvil_l1_urls_not_clobbered(plan):
    # set_l1_client_args must not overwrite the L1 URLs that set_anvil_args derived
    # with the names of ethereum-package services an anvil L1 never creates.
    (deployment_stages, args, op_args) = input_parser.parse_args(
        plan, _minimal_anvil_user_args()
    )
    expect.eq(args["l1_rpc_url"], "http://anvil-001:8545")
    expect.eq(args["l1_ws_url"], "ws://anvil-001:8545")
    expect.eq(args["l1_beacon_url"], "http://anvil-001:8545")


def test_parse_args_l1_client_args_still_apply_without_anvil(plan):
    # For a non-anvil L1 the ethereum-package service names are still derived.
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
    # The optimism-package needs an el_cl_genesis_data artifact that only the
    # ethereum-package L1 produces: fail with the real cause.
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


# agglayer_settle_confirmations and agglayer_settlement_policy are not anvil
# specific; the minimal anvil args are used as the smallest valid args block.


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


def _aggkit_ui_user_args(extra_args):
    return _with_args(
        _minimal_anvil_user_args(),
        {
            "additional_services": ["aggkit_proxy", "bridge_ui"],
            "bridge_ui_backend": "aggkit",
            "aggkit_proxy_url": "http://aggkit-proxy-001:8080",
        }
        | extra_args,
    )


def test_parse_args_bridge_ui_backend_happy_path(plan):
    user_args = _aggkit_ui_user_args(
        {
            "aggkit_deploy_dev_ui": True,
            "bridge_ui_l2_rpc_urls": [
                {
                    "path_suffix": "-001",
                    "url": "http://l2-anvil-001:8545",
                    "chain_id": 20201,
                    "network_id": 1,
                },
                {"path_suffix": "-002", "url": "http://l2-anvil-002:8545"},
            ],
            "aggkit_proxy_bridge_urls": [
                {"network_id": 0, "bridge_url": "http://aggkit-001:5577"},
            ],
            "aggkit_proxy_rpc_urls": [
                {"network_id": 0, "rpc_url": "http://anvil-001:8545"},
            ],
            "agglayer_extra_rollups": [
                {
                    "network_id": 2,
                    "op_el_rpc_url": "http://l2-anvil-002:8545",
                    "sequencer_address": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
                },
            ],
        }
    )
    (_, args, _) = input_parser.parse_args(plan, user_args)
    expect.eq(args["bridge_ui_backend"], "aggkit")


def test_parse_args_bridge_ui_backend_rejects_invalid(plan):
    user_args = _with_args(_minimal_anvil_user_args(), {"bridge_ui_backend": "bogus"})
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "Invalid bridge_ui_backend",
    )


def test_parse_args_aggkit_only_args_need_the_aggkit_backend(plan):
    for extra_args, message in [
        ({"aggkit_proxy_url": "http://aggkit-proxy-001:8080"}, "aggkit_proxy_url"),
        ({"aggkit_deploy_dev_ui": True}, "aggkit_deploy_dev_ui"),
    ]:
        user_args = _with_args(_minimal_anvil_user_args(), extra_args)
        expect.fails(
            lambda ua=user_args: input_parser.parse_args(plan, ua),
            message + " is only used with bridge_ui_backend",
        )


def test_parse_args_aggkit_proxy_url_must_be_plain_http(plan):
    for bad_url in [
        "https://aggkit-proxy-001:8080",
        "aggkit-proxy-001:8080",
        "http://aggkit-proxy-001:8080/",
    ]:
        user_args = _aggkit_ui_user_args({"aggkit_proxy_url": bad_url})
        expect.fails(
            lambda ua=user_args: input_parser.parse_args(plan, ua),
            "aggkit_proxy_url must",
        )


def test_parse_args_aggkit_backend_needs_a_bridge_api(plan):
    user_args = {
        "args": {
            "sequencer_type": constants.SEQUENCER_TYPE.cdk_erigon,
            "consensus_contract_type": constants.CONSENSUS_TYPE.rollup,
            "additional_services": ["bridge_ui"],
            "bridge_ui_backend": "aggkit",
        },
    }
    expect.fails(
        lambda: input_parser.parse_args(plan, user_args),
        "needs an aggkit bridge REST API",
    )

    user_args["args"]["aggkit_proxy_url"] = "http://aggkit-proxy-001:8080"
    input_parser.parse_args(plan, user_args)


def test_parse_args_bridge_ui_l2_rpc_urls_validation(plan):
    good = {"path_suffix": "-001", "url": "http://l2-anvil-001:8545"}
    for entries, message in [
        ([{"url": "http://x:8545"}], "non-empty string 'path_suffix'"),
        ([{"path_suffix": "-001"}], "non-empty string 'url'"),
        ([{"path_suffix": "001", "url": "http://x:8545"}], "must start with '-'"),
        ([good, good], "duplicate path_suffix"),
        (
            [{"path_suffix": "-001", "url": "https://x:8545"}],
            "must start with 'http://'",
        ),
        ([good | {"chain_id": 1}], "both chain_id and network_id"),
        ([good | {"network_id": 1}], "both chain_id and network_id"),
        ([good | {"chain_id": "1", "network_id": 1}], "integer 'chain_id'"),
        (["http://l2-anvil-001:8545"], "must be a mapping"),
    ]:
        user_args = _aggkit_ui_user_args({"bridge_ui_l2_rpc_urls": entries})
        expect.fails(lambda ua=user_args: input_parser.parse_args(plan, ua), message)


def test_parse_args_aggkit_proxy_maps_validation(plan):
    for arg_name, url_key in [
        ("aggkit_proxy_bridge_urls", "bridge_url"),
        ("aggkit_proxy_rpc_urls", "rpc_url"),
    ]:
        for entries, message in [
            ([{url_key: "http://x:1"}], "integer 'network_id'"),
            ([{"network_id": 0, "bridge": "http://x:1"}], "non-empty string"),
            ([{"network_id": -1, url_key: "http://x:1"}], "integer 'network_id'"),
            (
                [
                    {"network_id": 0, url_key: "http://x:1"},
                    {"network_id": 0, url_key: "http://y:1"},
                ],
                "duplicate network_id",
            ),
            ([{"network_id": 0, url_key: "x:1"}], "must be an http"),
        ]:
            user_args = _aggkit_ui_user_args({arg_name: entries})
            expect.fails(
                lambda ua=user_args: input_parser.parse_args(plan, ua), message
            )


def test_parse_args_agglayer_extra_rollups_validation(plan):
    good = {
        "network_id": 2,
        "op_el_rpc_url": "http://l2-anvil-002:8545",
        "sequencer_address": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
    }
    for entries, message in [
        (
            [{"network_id": 2, "rpc_url": "http://x:8545", "sequencer_address": "0x1"}],
            "op_el_rpc_url",
        ),
        ([good | {"network_id": 1}], "integer 'network_id' >= 2"),
        ([good | {"network_id": "2"}], "integer 'network_id' >= 2"),
        ([good, good], "duplicate network_id"),
        (
            [{k: v for k, v in good.items() if k != "sequencer_address"}],
            "sequencer_address",
        ),
    ]:
        user_args = _with_args(
            _minimal_anvil_user_args(), {"agglayer_extra_rollups": entries}
        )
        expect.fails(lambda ua=user_args: input_parser.parse_args(plan, ua), message)
