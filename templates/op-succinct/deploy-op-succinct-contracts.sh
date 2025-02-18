#!/bin/bash
# This script deploys the OP-Succinct contracts to the OP network.

# Checkout the v1.2.0 release
git fetch --all
git checkout -b op-succinct-v1.2.0 tags/op-succinct-v1.2.0

# Create the .env file
cd /opt/op-succinct
touch /opt/op-succinct/.env
echo "L1_RPC="http://el-1-geth-lighthouse:8545"
L1_BEACON_RPC="http://cl-1-lighthouse-geth:4000"
L2_RPC="http://op-el-1-op-geth-op-node-op-kurtosis:8545"
L2_NODE_RPC="http://op-cl-1-op-node-op-geth-op-kurtosis:8547"
PRIVATE_KEY="bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"
ETHERSCAN_API_KEY=\"\"
SUBMISSION_INTERVAL="10"

# Known after deploying mock verifier, will be replaced with the below command.
VERIFIER_ADDRESS="0x48b90E15Bd620e44266CCbba434C3f454a12b361"

# Known after deploying oracle, will be replaced with the below command.
L2OO_ADDRESS="0x0EeC8BC5B2A3879A9B8997100486F4e26a4f299f"
OP_SUCCINCT_MOCK="true"" > /opt/op-succinct/.env

# Update import ISemver which wouldn't run otherwise
sed -i 's|import {ISemver} from "src/universal/interfaces/ISemver.sol";|import {ISemver} from "@optimism/src/universal/interfaces/ISemver.sol";|' /opt/op-succinct/contracts/src/fp/OPSuccinctFaultDisputeGame.sol

# Deploy the mock-verifier and save the address to the verifier_address.json
just deploy-mock-verifier | grep -oP '0x[a-fA-F0-9]{40}' | xargs -I {} echo "VERIFIER_ADDRESS=\"{}\"" > /opt/op-succinct/verifier_address.json
# Update the VERIFIER_ADDRESS in the .env file with the output from the previous command
sed -i "s/^VERIFIER_ADDRESS=.*$/VERIFIER_ADDRESS=\"$(grep -oP '0x[a-fA-F0-9]{40}' /opt/op-succinct/verifier_address.json)\"/" /opt/op-succinct/.env

# Deploy the deploy-oracle and save the address to the l2oo_address.json
just deploy-oracle | grep -oP '0x[a-fA-F0-9]{40}' | xargs -I {} echo "L2OO_ADDRESS=\"{}\"" > /opt/op-succinct/l2oo_address.json
# Update the L2OO_ADDRESS in the .env file with the output from the previous command
sed -i "s/^L2OO_ADDRESS=.*$/L2OO_ADDRESS=\"$(grep -oP '0x[a-fA-F0-9]{40}' /opt/op-succinct/l2oo_address.json)\"/" /opt/op-succinct/.env

# Call upgrade-oracle
# cd /opt/op-succinct/contracts
# just upgrade-oracle 2>&1 | tee /opt/op-succinct/upgrade-oracle.out