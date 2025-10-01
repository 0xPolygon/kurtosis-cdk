op_input_parser = import_module("./op_input_parser.star")
op_sanity_check = import_module("./op_sanity_check.star")


def test_sanity_check_success(plan):
    args = {
        "zkevm_rollup_chain_id": 1001,
        "deployment_suffix": "-001",
        "l1_seconds_per_slot": 12,
    }
    op_args = {
        "chains": {
            "chain1": {
                "participants": {
                    "node1": {
                        "el": {
                            "el_image": "op-geth:latest",
                        },
                        "cl": {
                            "cl_image": "op-node:latest",
                        },
                    },
                },
                "network_params": {
                    "network_id": 1001,
                    "name": "001",
                    "seconds_per_slot": 2,
                },
            },
        },
    }
    source = op_input_parser.DEFAULT_NON_NATIVE_ARGS.get("source")
    op_sanity_check.sanity_check(plan, args, op_args, source)


def test_sanity_check_failure(plan):
    args = {
        "zkevm_rollup_chain_id": 1001,
        "deployment_suffix": "-001",
        "l1_seconds_per_slot": 12,
    }
    op_args = {
        "invalid_param": "value",
        "source": op_input_parser.DEFAULT_NON_NATIVE_ARGS.get("source"),
        "predeployed_contracts": True,
        "chains": {
            "chain1": {
                "participants": {
                    "node1": {
                        "el": {
                            "el_image": "op-geth:latest",
                        },
                        "cl": {
                            "cl_image": "op-node:latest",
                        },
                    },
                },
                "network_params": {
                    "network_id": 1001,
                    "name": "001",
                    "seconds_per_slot": 2,
                },
            },
        },
    }
    source = op_input_parser.DEFAULT_NON_NATIVE_ARGS.get("source")
    expect.fails(
        lambda: op_sanity_check.sanity_check(plan, args, op_args, source),
        "Invalid parameter invalid_param",
    )


def test_check_first_chain_id_success(plan):
    # Should pass when chain ID matches zkevm rollup chain ID
    args = {
        "zkevm_rollup_chain_id": 1001,
    }
    op_args = {
        "chains": {
            "chain1": {
                "network_params": {
                    "network_id": 1001,
                }
            }
        },
    }
    op_sanity_check.check_first_chain_id(args, op_args)


def test_check_first_chain_id_failure(plan):
    # Should fail when chain ID does not match zkevm rollup chain ID
    args = {
        "zkevm_rollup_chain_id": 1001,
    }
    op_args = {
        "chains": {
            "chain1": {
                "network_params": {
                    "network_id": 2002,
                }
            }
        },
    }
    expect.fails(
        lambda: op_sanity_check.check_first_chain_id(args, op_args),
        "The chain id of the first OP chain does not match the zkevm rollup chain id",
    )


def test_check_first_chain_name_success(plan):
    # Should pass when chain name matches deployment suffix
    args = {
        "deployment_suffix": "-001",
    }
    op_args = {
        "chains": {
            "chain1": {
                "network_params": {
                    "name": "001",
                }
            }
        }
    }
    op_sanity_check.check_first_chain_name(args, op_args)


def test_check_first_chain_name_failure(plan):
    # Should fail when chain name does not match deployment suffix
    args = {
        "deployment_suffix": "-001",
    }
    op_args = {
        "chains": {
            "chain1": {
                "network_params": {
                    "name": "002",
                }
            }
        }
    }
    expect.fails(
        lambda: op_sanity_check.check_first_chain_name(args, op_args),
        "The name of the first OP chain does not match the deployment suffix without the leading suffix '-'",
    )


def test_check_first_chain_block_time_success(plan):
    # Should pass when chain block time is less than or equal to L1 block time
    args = {
        "l1_seconds_per_slot": 12,
    }
    op_args = {
        "chains": {
            "chain1": {
                "network_params": {
                    "seconds_per_slot": 10,
                }
            }
        }
    }
    op_sanity_check.check_first_chain_block_time(args, op_args)


def test_check_first_chain_block_time_failure(plan):
    # Should fail when chain block time is greater than L1 block time
    args = {
        "l1_seconds_per_slot": 2,
    }
    op_args = {
        "chains": {
            "chain1": {
                "network_params": {
                    "seconds_per_slot": 10,
                }
            }
        }
    }
    expect.fails(
        lambda: op_sanity_check.check_first_chain_block_time(args, op_args),
        "The L2 block time of the first OP chain cannot be greater than the L1 block time",
    )
