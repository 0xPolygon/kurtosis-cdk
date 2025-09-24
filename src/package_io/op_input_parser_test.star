constants = import_module("./constants.star")
op_input_parser = import_module("./op_input_parser.star")


def test_parse_args_with_empty_args(plan):
    # Should return default args when no user args are provided
    user_args = {
        "deployment_suffix": "-001",
        "zkevm_rollup_chain_id": 2151908,
        "l1_seconds_per_slot": 2,
    }
    result = op_input_parser.parse_args(plan, user_args, {})
    optimism_package = result.get("optimism_package")

    # Check native fields
    chains = optimism_package.get("chains")
    expect.eq(len(chains), 1)
    chain0 = chains[0]

    participants = chain0.get("participants")
    expect.eq(len(participants), 1)
    participant0 = participants[0]
    expect.eq(participant0.get("count"), 1)
    expect.eq(
        participant0.get("el_image"), constants.DEFAULT_IMAGES.get("op_geth_image")
    )
    expect.eq(
        participant0.get("cl_image"), constants.DEFAULT_IMAGES.get("op_node_image")
    )

    proposer_params = chain0.get("proposer_params")
    expect.eq(
        proposer_params.get("image"),
        constants.DEFAULT_IMAGES.get("op_proposer_image"),
    )

    observability = optimism_package.get("observability")
    expect.eq(observability.get("enabled"), False)

    # Check meta (non-native) fields
    expect.eq(result.get("predeployed_contracts"), True)


def test_parse_args_with_user_overrides(plan):
    # Should correctly apply user overrides while preserving defaults
    user_args = {
        "deployment_suffix": "-001",
        "zkevm_rollup_chain_id": 2151908,
        "l1_seconds_per_slot": 2,
    }
    user_op_args = {
        # meta configuration - non-native fields
        "predeployed_contracts": False,
        # native configuration - optimism-package fields
        "chains": [
            {
                "participants": [
                    {
                        "cl_image": "op-node:latest",
                    }
                ],
                "proposer_params": {
                    "enabled": False,
                },
            },
            {
                "participants": [
                    {
                        "el_image": "op-geth:latest",
                    }
                ],
                "network_params": {
                    "seconds_per_slot": 12,
                },
            },
            {
                "batcher_params": {
                    "image": "op-batcher:latest",
                },
            },
            {},
        ],
        "observability": {
            "enabled": True,
        },
    }

    result = op_input_parser.parse_args(plan, user_args, user_op_args)
    optimism_package = result.get("optimism_package")

    # Check chains structure
    chains = optimism_package.get("chains")
    expect.eq(len(chains), 4)

    ## Chain 0: Custom CL image, proposer disabled, defaults elsewhere
    chain0 = chains[0]
    participants0 = chain0.get("participants")
    expect.eq(len(participants0), 1)

    participant0 = participants0[0]
    proposer_params0 = chain0.get("proposer_params")
    batcher_params0 = chain0.get("batcher_params")
    network_params0 = chain0.get("network_params")
    # overrides
    expect.eq(participant0.get("cl_image"), "op-node:latest")
    expect.eq(proposer_params0.get("enabled"), False)

    # defaults
    expect.eq(
        participant0.get("el_image"), constants.DEFAULT_IMAGES.get("op_geth_image")
    )
    expect.eq(
        proposer_params0.get("image"),
        constants.DEFAULT_IMAGES.get("op_proposer_image"),
    )
    expect.eq(
        batcher_params0.get("image"),
        constants.DEFAULT_IMAGES.get("op_batcher_image"),
    )
    expect.eq(network_params0.get("seconds_per_slot"), 1)
    expect.eq(network_params0.get("name"), "001")

    ## Chain 1: Custom EL image, custom network params, defaults elsewhere
    chain1 = chains[1]
    participants1 = chain1.get("participants")
    expect.eq(len(participants1), 1)

    participant1 = participants1[0]
    proposer_params1 = chain1.get("proposer_params")
    batcher_params1 = chain1.get("batcher_params")
    network_params1 = chain1.get("network_params")

    # overrides
    expect.eq(participant1.get("el_image"), "op-geth:latest")
    expect.eq(network_params1.get("seconds_per_slot"), 12)

    # defaults
    expect.eq(
        participant1.get("cl_image"), constants.DEFAULT_IMAGES.get("op_node_image")
    )
    expect.eq(
        proposer_params1.get("image"),
        constants.DEFAULT_IMAGES.get("op_proposer_image"),
    )
    expect.eq(
        batcher_params1.get("image"),
        constants.DEFAULT_IMAGES.get("op_batcher_image"),
    )
    expect.eq(network_params1.get("name"), "001")

    ## Chain 2: Custom batcher params, defaults elsewhere
    chain2 = chains[2]
    participants2 = chain2.get("participants")
    expect.eq(len(participants2), 1)

    participant2 = participants2[0]
    proposer_params2 = chain2.get("proposer_params")
    batcher_params2 = chain2.get("batcher_params")
    network_params2 = chain2.get("network_params")

    # overrides
    expect.eq(batcher_params2.get("image"), "op-batcher:latest")

    # defaults
    expect.eq(
        participant2.get("el_image"), constants.DEFAULT_IMAGES.get("op_geth_image")
    )
    expect.eq(
        participant2.get("cl_image"), constants.DEFAULT_IMAGES.get("op_node_image")
    )
    expect.eq(
        proposer_params2.get("image"),
        constants.DEFAULT_IMAGES.get("op_proposer_image"),
    )
    expect.eq(network_params2.get("seconds_per_slot"), 1)
    expect.eq(network_params2.get("name"), "001")

    ## Chain 3: Empty config, all defaults
    chain3 = chains[3]
    expect.eq(chain3, op_input_parser.DEFAULT_CHAIN)

    # Check op_contract_deployer_params defaults
    op_contract_deployer_params = optimism_package.get("op_contract_deployer_params")
    expect.eq(
        op_contract_deployer_params.get("image"),
        constants.DEFAULT_IMAGES.get("op_contract_deployer_image"),
    )

    # Check meta (non-native) fields
    # overrides
    expect.eq(result.get("predeployed_contracts"), False)
    # defaults
    expect.eq(
        result.get("source"),
        "github.com/agglayer/optimism-package/main.star@cc37713aff9c4955dd6975cdbc34072a1286754e",
    )

    # Check external_l1_network_params exists
    external_l1 = result.get("external_l1_network_params")
    expect.ne(external_l1, None)
