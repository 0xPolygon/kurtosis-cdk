# Anvil L1

You can configure the stack to use Anvil as L1 by setting
```
l1_engine: anvil
```

Please, understand that by doing:
- ```l1_chain_id``` is taken into account
- ```l1_rpc_url``` is automatically set to http://anvil-001:8545
- ```l1_ws_url``` is automatically set to ws://anvil-001:8545
- These params are ignored:
    - ```l1_beacon_url```
    - ```l1_additional_services```
    - ```l1_preset```
    - ```l1_seconds_per_slot```
    - ```l1_participants_count```

## Parameters
These are optional config params for Anvil:
- ```l1_anvil_block_time```: seconds per block
- ```l1_anvil_slots_in_epoch```: number of slots in an epoch

For instance setting
- ```l1_anvil_block_time: 6```
- ```l1_anvil_slots_in_epoch: 32```

Will produce blocks each 6 seconds, and the most recent safe block will be the latest one - 32 (that one from 32 * 6 seconds ago).


## State dump and recover
By using Anvil as L1, you can dump L1 network state, totally remove the network, and recreate again with the same L1 state.
This procedure has been tested with zkEVM rollup mode, for other scenarios you could need to perform additional steps (like dumping/restoring DAC database) or could be even not supported.

### Procedure
Deploy the network.
```bash
ENCLAVE=cdk
kurtosis run --enclave $ENCLAVE . '{
    "args": {
        "l1_engine": "anvil",
        "consensus_contract_type": "rollup",
    }
}'
```

Once deployed, save the required files to recreate again later. These are the files you need:
- ./anvil_state.json
- ./templates/contract-deploy/
- ./templates/contract-deploy/combined.json
- ./templates/contract-deploy/genesis.json
- ./templates/contract-deploy/dynamic-kurtosis-conf.json
- ./templates/contract-deploy/dynamic-kurtosis-allocs.json

Let's get them:

```bash
STATE_FILE=anvil_state.json
DEPLOYMENT_FILES="combined.json genesis.json dynamic-kurtosis-conf.json dynamic-kurtosis-allocs.json"

contracts_uuid=$(kurtosis enclave inspect --full-uuids $ENCLAVE | grep contracts | awk '{ print $1 }')
for file in $DEPLOYMENT_FILES; do
    # Save each file on ./templates/contract-deploy, as they are expected there for use_previously_deployed_contracts=True
    docker cp contracts-001--$contracts_uuid:/opt/output/$file ./templates/contract-deploy/$file
done

# Dump Anvil state (L1)
anvil_uuid=$(kurtosis enclave inspect --full-uuids $ENCLAVE | grep anvil | awk '{ print $1 }')
docker cp anvil-001--$anvil_uuid:/tmp/state_out.json $STATE_FILE
```

At that point you have all you need, you can totally remove the network.
```bash
kurtosis enclave stop $ENCLAVE
kurtosis enclave rm $ENCLAVE
```

To recreate the network, run kurtosis from scratch like this:
```bash
time kurtosis run --enclave $ENCLAVE . '{
    "args": {
        "anvil_state_file": '$STATE_FILE',
        "use_previously_deployed_contracts": true,
        "consensus_contract_type": "rollup",
    }
}'
```

This will perform the required steps to load the previous state, however, the sequencer needs to recover the state from L1 so it has been set with a specific param, that won't allow it to resume generating new blocks. So you need to manually unlock it:

```bash
# Check cdk-erigon-sequencer logs until you see lines like this before proceeding.
#  "L1 block sync recovery has completed!"

# Disable L1 recovery mode
kurtosis service exec $ENCLAVE cdk-erigon-sequencer-001 \
    "sed -i 's/zkevm.l1-sync-start-block: 1/zkevm.l1-sync-start-block: 0/' /etc/cdk-erigon/config.yaml"

# Restart sequenccer
kurtosis service stop $ENCLAVE cdk-erigon-sequencer-001
kurtosis service start $ENCLAVE cdk-erigon-sequencer-001
```
