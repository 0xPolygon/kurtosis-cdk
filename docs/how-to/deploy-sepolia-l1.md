# Deploy Kurtosis CDK with Sepolia as L1

Deploying to Sepolia will require the L1 related parameters to be changed.

## params.yml
Change `deploy_l1` to `false`.
```
# Deploy local L1.
deploy_l1: false
```

Change the `l1_chain_id`, `l1_preallocated_mnemonic`, `l1_rpc_url`, `l1_ws_url`, and `l1_funding_amount` as needed.
```
l1_chain_id: 11155111
# The first account for the mnemonic should have enough funds to cover the deployment costs and the l1_funding_amount transfers to L1 addresses.
l1_preallocated_mnemonic: <mnemonic_for_a_funded_L1_account>
# The amount of initial funding to L1 addresses performing services like the Sequencer, Aggregator, Admin, Agglayer, Claimtxmanager. 
l1_funding_amount: 1ether
l1_rpc_url: <Sepolia_RPC_URL>
l1_ws_url: <Sepolia_WS_URL>
```

## cdk_bridge_infra.star

Comment out the below:
```
...
# l1rpc_service = plan.get_service("el-1-geth-lighthouse")
...
# "l1rpc_ip": l1rpc_service.ip_address,
# "l1rpc_port": l1rpc_service.ports["rpc"].number,
```

## templates/bridge-infra/haproxy.cfg

Comment out the below:
```
...
    # acl url_l1rpc path_beg /l1rpc
...
    # use_backend backend_l1rpc if url_l1rpc
...   
# backend backend_l1rpc
#     http-request set-path /
#     server server1 {{.l1rpc_ip}}:{{.l1rpc_port}}
```