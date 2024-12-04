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


def run(plan, args):
    private_key_result = plan.run_sh(
        description="Derive private key from mnemonic",
        run="cast wallet private-key --mnemonic {}".format(
            args["l1_preallocated_mnemonic"]
        ),
    )
    private_key = private_key_result.output

    optimism_package.run(
        plan,
        {
            "optimism_package": {
                "chains": [
                    {
                        "participants": [
                            {
                                "el_type": "op-geth",
                                "el_image": OP_GETH_IMAGE,
                                "cl_type": "op-node",
                                "cl_image": OP_NODE_IMAGE,
                                "count": 1,
                            }
                        ]
                    }
                ],
                "op_contract_deployer_params": {
                    "image": OP_DEPLOYER_IMAGE,
                    "l1_artifacts_locator": "tag://op-contracts/v1.6.0",
                    "l2_artifacts_locator": "tag://op-contracts/v1.7.0-beta.1+l2-contracts",
                },
            },
            "external_l1_network_params": {
                "network_id": args["l1_chain_id"],
                "rpc_kind": "standard",
                "el_rpc_url": args["l1_rpc_url"],
                "el_ws_url": args["l1_ws_url"],
                "cl_rpc_url": args["l1_beacon_url"],
                "priv_key": private_key,
            },
        },
    )
