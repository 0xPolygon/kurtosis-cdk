op_sanity_check = import_module("./op_sanity_check.star")


def test_sanity_check_success(plan):
    args = {
        "zkevm_rollup_chain_id": 1001,
        "deployment_suffix": "-001",
        "l1_seconds_per_slot": 12,
    }
    op_args = {
        "chains": [
            {
                "participants": [
                    {
                        "el_image": "op-geth:latest",
                        "cl_image": "op-node:latest",
                    }
                ],
                "network_params": {
                    "network_id": 1001,
                    "name": "001",
                    "seconds_per_slot": 2,
                },
            }
        ]
    }
    source = "github.com/agglayer/optimism-package/main.star@a70f83d31c746139d8b6155bdec6a26fdd4afda0"
    op_sanity_check.sanity_check(plan, args, op_args, source)


def test_sanity_check_failure(plan):
    args = {
        "zkevm_rollup_chain_id": 1001,
        "deployment_suffix": "-001",
        "l1_seconds_per_slot": 12,
    }
    op_args = {
        "invalid_param": "value",
        "source": "github.com/agglayer/optimism-package/main.star@cc37713aff9c4955dd6975cdbc34072a1286754e",
        "predeployed_contracts": True,
        "chains": [
            {
                "participants": [
                    {
                        "el_image": "op-geth:latest",
                        "cl_image": "op-node:latest",
                    }
                ],
                "network_params": {
                    "network_id": 1001,
                    "name": "001",
                    "seconds_per_slot": 2,
                },
            }
        ],
    }
    source = "github.com/agglayer/optimism-package/src/package_io/sanity_check.star@cc37713aff9c4955dd6975cdbc34072a1286754e"
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
        "chains": [
            {
                "network_params": {
                    "network_id": 1001,
                }
            }
        ]
    }
    op_sanity_check.check_first_chain_id(args, op_args)


def test_check_first_chain_id_failure(plan):
    # Should fail when chain ID does not match zkevm rollup chain ID
    args = {
        "zkevm_rollup_chain_id": 1001,
    }
    op_args = {
        "chains": [
            {
                "network_params": {
                    "network_id": 2002,
                }
            }
        ]
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
        "chains": [
            {
                "network_params": {
                    "name": "001",
                }
            }
        ]
    }
    op_sanity_check.check_first_chain_name(args, op_args)


def test_check_first_chain_name_failure(plan):
    # Should fail when chain name does not match deployment suffix
    args = {
        "deployment_suffix": "-001",
    }
    op_args = {
        "chains": [
            {
                "network_params": {
                    "network_id": "002",
                }
            }
        ]
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
        "chains": [
            {
                "network_params": {
                    "seconds_per_slot": 10,
                }
            }
        ]
    }
    op_sanity_check.check_first_chain_block_time(args, op_args)


def test_check_first_chain_block_time_failure(plan):
    # Should fail when chain block time is greater than L1 block time
    args = {
        "l1_seconds_per_slot": 2,
    }
    op_args = {
        "chains": [
            {
                "network_params": {
                    "seconds_per_slot": 10,
                }
            }
        ]
    }
    expect.fails(
        lambda: op_sanity_check.check_first_chain_block_time(args, op_args),
        "The L2 block time of the first OP chain cannot be greater than the L1 block time",
    )
