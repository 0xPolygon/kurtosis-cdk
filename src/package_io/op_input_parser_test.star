constants = import_module("./constants.star")
op_input_parser = import_module("./op_input_parser.star")


def test_sort_dict_by_values(plan):
    # Should sort dictionary by keys alphabetically
    unsorted_dict = {
        "zebra": 1,
        "alpha": 2,
        "beta": 3,
    }

    result = op_input_parser._sort_dict_by_values(unsorted_dict)
    keys = list(result.keys())

    expect.eq(keys[0], "alpha")
    expect.eq(keys[1], "beta")
    expect.eq(keys[2], "zebra")
    expect.eq(result.get("alpha"), 2)
    expect.eq(result.get("beta"), 3)
    expect.eq(result.get("zebra"), 1)


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
    expect.eq(len(chains.keys()), 1)
    chain1 = chains.get("001")

    participants = chain1.get("participants")
    expect.eq(len(participants.keys()), 1)
    node1 = participants.get("node1")
    expect.eq(
        node1.get("el").get("image"),
        constants.DEFAULT_IMAGES.get("op_geth_image"),
    )
    expect.eq(
        node1.get("cl").get("image"),
        constants.DEFAULT_IMAGES.get("op_node_image"),
    )

    proposer_params = chain1.get("proposer_params")
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
        "log_format": "json",
        "zkevm_rollup_chain_id": 2151908,
        "l1_seconds_per_slot": 2,
    }
    user_op_args = {
        # meta configuration - non-native fields
        "predeployed_contracts": False,
        # native configuration - optimism-package fields
        "chains": {
            "001": {
                "participants": {
                    "node1": {
                        "cl": {
                            "image": "op-node:latest",
                        },
                    }
                },
                "proposer_params": {
                    "enabled": False,
                },
            },
            "002": {
                "participants": {
                    "node1": {
                        "el": {
                            "image": "op-geth:latest",
                        },
                    },
                },
                "network_params": {
                    "seconds_per_slot": 12,
                },
            },
            "003": {
                "batcher_params": {
                    "image": "op-batcher:latest",
                },
            },
            "004": {},
        },
        "observability": {
            "enabled": False,
        },
    }

    result = op_input_parser.parse_args(plan, user_args, user_op_args)
    optimism_package = result.get("optimism_package")

    # Check chains structure
    chains = optimism_package.get("chains")
    expect.eq(len(chains.keys()), 4)

    ## Chain 1: Custom CL image, proposer disabled, defaults elsewhere
    chain1 = chains.get("001")
    participants1 = chain1.get("participants")
    expect.eq(len(participants1.keys()), 1)

    node1 = participants1.get("node1")
    proposer_params1 = chain1.get("proposer_params")
    batcher_params1 = chain1.get("batcher_params")
    network_params1 = chain1.get("network_params")
    # overrides
    expect.eq(node1.get("cl").get("image"), "op-node:latest")
    expect.eq(proposer_params1.get("enabled"), False)

    # defaults
    expect.eq(
        node1.get("el").get("image"), constants.DEFAULT_IMAGES.get("op_geth_image")
    )
    expect.eq(
        proposer_params1.get("image"),
        constants.DEFAULT_IMAGES.get("op_proposer_image"),
    )
    expect.eq(
        batcher_params1.get("image"),
        constants.DEFAULT_IMAGES.get("op_batcher_image"),
    )
    expect.eq(network_params1.get("seconds_per_slot"), 1)

    ## Chain 2: Custom EL image, custom network params, defaults elsewhere
    chain2 = chains.get("002")
    participants2 = chain2.get("participants")
    expect.eq(len(participants2.keys()), 1)

    node2 = participants2.get("node1")
    proposer_params2 = chain2.get("proposer_params")
    batcher_params2 = chain2.get("batcher_params")
    network_params2 = chain2.get("network_params")

    # overrides
    expect.eq(node2.get("el").get("image"), "op-geth:latest")
    expect.eq(network_params2.get("seconds_per_slot"), 12)

    # defaults
    expect.eq(
        node2.get("cl").get("image"), constants.DEFAULT_IMAGES.get("op_node_image")
    )
    expect.eq(
        proposer_params2.get("image"),
        constants.DEFAULT_IMAGES.get("op_proposer_image"),
    )
    expect.eq(
        batcher_params2.get("image"),
        constants.DEFAULT_IMAGES.get("op_batcher_image"),
    )

    ## Chain 3: Custom batcher params, defaults elsewhere
    chain3 = chains.get("003")
    participants3 = chain3.get("participants")
    expect.eq(len(participants3.keys()), 1)

    node3 = participants3.get("node1")
    proposer_params3 = chain3.get("proposer_params")
    batcher_params3 = chain3.get("batcher_params")
    network_params3 = chain3.get("network_params")

    # overrides
    expect.eq(batcher_params3.get("image"), "op-batcher:latest")

    # defaults
    expect.eq(
        node3.get("el").get("image"), constants.DEFAULT_IMAGES.get("op_geth_image")
    )
    expect.eq(
        node3.get("cl").get("image"), constants.DEFAULT_IMAGES.get("op_node_image")
    )
    expect.eq(
        proposer_params3.get("image"),
        constants.DEFAULT_IMAGES.get("op_proposer_image"),
    )
    expect.eq(network_params3.get("seconds_per_slot"), 1)

    ## Chain 4: Empty config, all defaults
    chain4 = chains.get("004")
    expect.eq(chain4, op_input_parser._default_chain())

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
    expect.contains(
        result.get("source"),
        "github.com/agglayer/optimism-package",
    )

    # Check external_l1_network_params exists
    external_l1 = result.get("external_l1_network_params")
    expect.ne(external_l1, None)


def test_parse_chains_with_empty_chains(plan):
    # Should return default chain when empty dict is provided
    result = op_input_parser._parse_chains({})
    expect.eq(len(result.keys()), 1)
    expect.eq(result.get("001"), op_input_parser._default_chain())


def test_parse_chains_with_partial_config(plan):
    # Should apply defaults to partially configured chains
    chains = {
        "001": {
            "network_params": {
                "seconds_per_slot": 5,
            },
        },
        "002": {
            "batcher_params": {
                "image": "custom-batcher:latest",
            },
        },
    }
    result = op_input_parser._parse_chains(chains)
    expect.eq(len(result.keys()), 2)

    # First chain should have custom network params but default everything else
    chain1 = result.get("001")
    expect.eq(chain1.get("network_params").get("seconds_per_slot"), 5)
    default_participants = op_input_parser._default_chain().get("participants")
    expect.eq(chain1.get("participants"), default_participants)

    # Second chain should have custom batcher but default everything else
    chain2 = result.get("002")
    expect.eq(chain2.get("batcher_params").get("image"), "custom-batcher:latest")
    expect.eq(chain2.get("participants"), default_participants)


def test_parse_participants_with_empty_participants(plan):
    # Should return default participant when empty dict is provided
    result = op_input_parser._parse_participants({})
    expect.eq(len(result.keys()), 1)
    expect.eq(result.get("node1"), op_input_parser._default_participant())


def test_parse_participants_with_partial_config(plan):
    # Should apply defaults to partially configured participants
    participants = {
        "node1": {
            "el": {
                "image": "custom-geth:latest",
            },
        },
        "node2": {
            "cl": {
                "image": "custom-node:latest",
            },
        },
    }

    result = op_input_parser._parse_participants(participants)
    expect.eq(len(result.keys()), 2)

    # First participant should have custom EL image but default CL image
    node1 = result.get("node1")
    expect.eq(node1.get("el").get("image"), "custom-geth:latest")
    expect.eq(
        node1.get("cl").get("image"), constants.DEFAULT_IMAGES.get("op_node_image")
    )

    # Second participant should have custom CL image but default everything else
    node2 = result.get("node2")
    expect.eq(node2.get("cl").get("image"), "custom-node:latest")
    expect.eq(
        node2.get("el").get("image"), constants.DEFAULT_IMAGES.get("op_geth_image")
    )


def test_get_l1_config(plan):
    # Should properly extract and format L1 configuration
    user_args = {
        "l1_chain_id": "11155111",
        "l1_rpc_url": "http://localhost:8545",
        "l1_ws_url": "ws://localhost:8546",
        "l1_beacon_url": "http://localhost:5052",
        "l1_preallocated_mnemonic": "test test test test test test test test test test test junk",
    }

    result = op_input_parser._get_l1_config(plan, user_args)

    expect.eq(result.get("network_id"), "11155111")
    expect.eq(result.get("el_rpc_url"), "http://localhost:8545")
    expect.eq(result.get("el_ws_url"), "ws://localhost:8546")
    expect.eq(result.get("cl_rpc_url"), "http://localhost:5052")
    expect.eq(result.get("rpc_kind"), "standard")
