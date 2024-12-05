constants = import_module("./src/package_io/constants.star")

optimism_package = import_module(
    "github.com/leovct/optimism-package/main.star@feat/deploy-to-external-l1"
    # "github.com/ethpandaops/ethereum-package/main.star@1.1.0"
)

# https://github.com/ethereum-optimism/op-geth/releases
OP_GETH_IMAGE = (
    "https://us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101411.3"
)

# https://github.com/ethereum-optimism/optimism/releases
OP_NODE_IMAGE = (
    "https://us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.10.1"
)

# https://github.com/ethereum-optimism/optimism/releases?q=op-deployer
OP_DEPLOYER_IMAGE = "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-deployer:v0.0.7"
OP_DEPLOYER_L1_ARTIFACTS_LOCATOR = "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-9af7366a7102f51e8dbe451dcfa22971131d89e218915c91f420a164cc48be65.tar.gz"
OP_DEPLOYER_L2_ARTIFACTS_LOCATOR = "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-9af7366a7102f51e8dbe451dcfa22971131d89e218915c91f420a164cc48be65.tar.gz"


def run(plan, args):
    private_key_result = plan.run_sh(
        description="Derive private key from mnemonic",
        run="cast wallet private-key --mnemonic \"{}\" | tr -d '\n'".format(
            args["l1_preallocated_mnemonic"]
        ),
        image=constants.TOOLBOX_IMAGE,
    )
    private_key = private_key_result.output
    plan.print(private_key)

    optimism_args = args.get("optimism_package") or default_optimism_args()
    optimism_package.run(
        plan,
        {
            "optimism_package": optimism_args,
            "external_l1_network_params": {
                "network_id": str(args["l1_chain_id"]),
                "rpc_kind": "standard",
                "el_rpc_url": args["l1_rpc_url"],
                "el_ws_url": args["l1_ws_url"],
                "cl_rpc_url": args["l1_beacon_url"],
                "priv_key": private_key,
            },
        },
    )


def default_optimism_args():
    return {
        "chains": [
            {
                "participants": [
                    {
                        "el_type": "op-geth",
                        "el_image": OP_GETH_IMAGE,
                        "cl_type": "op-node",
                        "cl_image": OP_NODE_IMAGE,
                        "count": 1,
                    },
                ],
            },
        ],
        "op_contract_deployer_params": {
            "image": OP_DEPLOYER_IMAGE,
            "l1_artifacts_locator": OP_DEPLOYER_L1_ARTIFACTS_LOCATOR,
            "l2_artifacts_locator": OP_DEPLOYER_L2_ARTIFACTS_LOCATOR,
        },
    }
