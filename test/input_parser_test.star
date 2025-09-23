input_parser = import_module("../input_parser.star")


def test_get_op_stack_args_with_empty_args(plan):
    # Should use default images when no custom arguments are provided
    result = input_parser.get_op_stack_args(plan, {}, {})
    optimism_package = result.get("optimism_package", {})
    chains = optimism_package.get("chains", [])
    expect.eq(len(chains), 1)
    chain0 = chains[0]
    participants = chain0.get("participants", [])
    expect.eq(len(participants), 1)
    participant0 = participants[0]
    el_image = participant0.get("el_image")
    cl_image = participant0.get("cl_image")
    expect.eq(el_image, input_parser.DEFAULT_IMAGES.get("op_geth_image"))
    expect.eq(cl_image, input_parser.DEFAULT_IMAGES.get("op_node_image"))


def test_get_op_stack_args_with_proposer_disabled(plan):
    # Should use default images when proposer is explicitly disabled
    user_op_stack_args = {
        "chains": [
            {
                "proposer_params": {
                    "enabled": False,
                },
            }
        ]
    }
    result = input_parser.get_op_stack_args(plan, {}, user_op_stack_args)

    optimism_package = result.get("optimism_package", {})
    chains = optimism_package.get("chains", [])
    expect.eq(len(chains), 1)
    chain0 = chains[0]
    participants = chain0.get("participants", [])
    expect.eq(len(participants), 1)
    participant0 = participants[0]
    el_image = participant0.get("el_image")
    cl_image = participant0.get("cl_image")
    expect.eq(el_image, input_parser.DEFAULT_IMAGES.get("op_geth_image"))
    expect.eq(cl_image, input_parser.DEFAULT_IMAGES.get("op_node_image"))


def test_get_op_stack_args_with_custom_el_image(plan):
    # Should use custom EL image and default CL image when only EL image is specified
    user_op_stack_args = {
        "chains": [
            {
                "participants": [
                    {
                        "el_image": "op-geth:latest",
                    }
                ],
                "proposer_params": {
                    "enabled": False,
                },
            }
        ]
    }
    result = input_parser.get_op_stack_args(plan, {}, user_op_stack_args)

    optimism_package = result.get("optimism_package", {})
    chains = optimism_package.get("chains", [])
    expect.eq(len(chains), 1)
    chain0 = chains[0]
    participants = chain0.get("participants", [])
    expect.eq(len(participants), 1)
    participant0 = participants[0]
    el_image = participant0.get("el_image")
    cl_image = participant0.get("cl_image")
    expect.eq(el_image, "op-geth:latest")
    expect.eq(cl_image, input_parser.DEFAULT_IMAGES.get("op_node_image"))


def test_get_op_stack_args_with_custom_cl_image(plan):
    # Should use custom CL image and default EL image when only CL image is specified
    user_op_stack_args = {
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
            }
        ]
    }
    result = input_parser.get_op_stack_args(plan, {}, user_op_stack_args)

    optimism_package = result.get("optimism_package", {})
    chains = optimism_package.get("chains", [])
    expect.eq(len(chains), 1)
    chain0 = chains[0]
    participants = chain0.get("participants", [])
    expect.eq(len(participants), 1)
    participant0 = participants[0]
    el_image = participant0.get("el_image")
    cl_image = participant0.get("cl_image")
    expect.eq(el_image, input_parser.DEFAULT_IMAGES.get("op_geth_image"))
    expect.eq(cl_image, "op-node:latest")
