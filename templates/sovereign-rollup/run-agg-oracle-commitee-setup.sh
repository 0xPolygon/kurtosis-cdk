#!/usr/bin/env bash
set -e

pushd /opt/zkevm-contracts || exit 1

# Deploy aggoracle committee contract on L2
# https://github.com/agglayer/specs/pull/38/files#diff-2112592f510ad7a3f0a6ebbe579661d6e94ff1f45ec97cc4f624963e2dbda69a

# First replace polygonZkEVMGlobalExitRootL2Address with valid address, then move the param file into correct directory
jq --arg germanagerl2addr "$(jq -r '.polygonZkEVMGlobalExitRootL2Address' /opt/zkevm/combined.json)" \
  '.globalExitRootManagerL2SovereignAddress = $germanagerl2addr' \
  /opt/contract-deploy/deploy-agg-oracle-commitee.json > /opt/contract-deploy/deploy-agg-oracle-commitee.json.tmp && \
mv /opt/contract-deploy/deploy-agg-oracle-commitee.json.tmp /opt/zkevm-contracts/tools/deployAggOracleCommittee/deploy_parameters.json

# Comment out and skip etherscan verification
sed -i '/await verifyContractEtherscan/,/]);/ s/^/\/\//g' /opt/zkevm-contracts/tools/deployAggOracleCommittee/deployAggOracleCommittee.ts

# Remove strictEqual check on L2 GER Manager address
sed -i 's/expect(contractGlobalExitRootManager).to.be.equal(globalExitRootManagerL2SovereignAddress);/expect(contractGlobalExitRootManager.toLowerCase()).to.be.equal(globalExitRootManagerL2SovereignAddress.toLowerCase());/' /opt/zkevm-contracts/tools/deployAggOracleCommittee/deployAggOracleCommittee.ts

# Deploy to L2
DEPLOYER_PRIVATE_KEY="{{ .zkevm_l2_admin_private_key }}" \
CUSTOM_PROVIDER="http://{{ .l2_rpc_name }}:8545" \
 npx hardhat run tools/deployAggOracleCommittee/deployAggOracleCommittee.ts --network custom 2>&1 | tee 08_create_rollup_type.out

# Merge AggOracle committee deployment output into combined.json
TMP_FILE=$(mktemp) && jq -s '.[0] * (.[1] | del(.gitInfo))' /opt/zkevm/combined.json /opt/zkevm-contracts/tools/deployAggOracleCommittee/deploy_output.json > "$TMP_FILE" && mv "$TMP_FILE" /opt/zkevm/combined.json