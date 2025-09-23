#! /bin/bash

ENCLAVE_NAME=legacy
BASE_NETWORK=.github/tests/tmp_integration_scenarios/4_opgeth_legacy.yml

kurtosis run --enclave=$ENCLAVE_NAME . --args-file=$BASE_NETWORK

NETWORK_ARGS='{ 
    "deployment_stages": {
        "deploy_l1": false,
        "deploy_agglayer": false,
        "deploy_op_succinct": false
    },
    "args": {
        "aggkit_image": "ghcr.io/agglayer/aggkit:0.7.0-beta5",
        "agglayer_image": "ghcr.io/agglayer/agglayer:0.4.0-rc.9",
        "agglayer_contracts_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-contracts:v0.0.0-rc.3.aggchain.multisig-fork.0",
        "consensus_contract_type": "ecdsa_multisig",
        "use_agg_sender_validator": false,
        "use_agg_oracle_committee": false,
        "agglayer_prover_primary_prover": "network-prover",
        "sp1_prover_key": "xxxxxx",
        "zkevm_use_real_verifier": true,
        "deployment_suffix": "-002",
        "zkevm_rollup_id": 2,
        "zkevm_rollup_chain_id": 20202
    },
    "optimism_package": {
        "chains": [
            {
                "proposer_params": {
                    "enabled": false
                },
                "challenger_params": {
                    "enabled": false
                },
                "network_params": {
                    "name": "002",
                    "network_id": "20202",
                    "seconds_per_slot": 1
                }
            }
        ],
        "observability": {
            "enabled": false
        }
    }
}'

# LET'S DEPLOY A SECOND NETWORK WITH CURRENT VERSIONS BUT COMMITEES SET TO FALSE
kurtosis run --enclave "$ENCLAVE_NAME" . "$NETWORK_ARGS"

# LETS DEPLOY A THIRD NETWORK WITH COMMITTEES SET AND JUST 1 MEMBER
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.args.deployment_suffix = "-003" | .args.zkevm_rollup_id = 3 | .args.zkevm_rollup_chain_id = 30303')
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.optimism_package.chains[0].network_params.name = "003" | .optimism_package.chains[0].network_params.network_id = "30303"')
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.args.use_agg_sender_validator = true | .args.use_agg_oracle_committee = true')
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.args.agg_oracle_committee_total_members = 1 | .args.agg_oracle_committee_quorum = 1 | .args.agg_sender_validator_total_number = 1 | .args.agg_sender_multisig_threshold = 1')

kurtosis run --enclave "$ENCLAVE_NAME" . "$NETWORK_ARGS"

# LETS DEPLOY A FOURTH NETWORK WITH COMMITTEES SET AND FEW MEMBERS
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.args.deployment_suffix = "-004" | .args.zkevm_rollup_id = 4 | .args.zkevm_rollup_chain_id = 40404')
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.optimism_package.chains[0].network_params.name = "004" | .optimism_package.chains[0].network_params.network_id = "40404"')
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.args.use_agg_sender_validator = true | .args.use_agg_oracle_committee = true')
NETWORK_ARGS=$(echo $NETWORK_ARGS | jq '.args.agg_oracle_committee_total_members = 5 | .args.agg_oracle_committee_quorum = 3 | .args.agg_sender_validator_total_number = 5 | .args.agg_sender_multisig_threshold = 3')

kurtosis run --enclave "$ENCLAVE_NAME" . "$NETWORK_ARGS"
