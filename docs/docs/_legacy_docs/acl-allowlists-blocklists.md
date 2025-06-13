# ACL - Allowlisting and Blocklisting Addresses in CDK

CDK offers ACLs which allow the network operator to enforce an allowlist and blocklist within the network. ACL is a command that can be used within the cdk-erigon sequencer.

**The ACL must be setup within the cdk-erigon sequencer**, and the policies are applied on a network level. Permissionless RPCs setting up ACLs will have no effect on the network!

Spin up a Kurtosis CDK environment and get a shell in the cdk-erigon sequencer service. The ACL [command](https://github.com/0xPolygonHermez/cdk-erigon/tree/zkevm/cmd/acl) is built within cdk-erigon by default.

```bash
kurtosis service shell cdk cdk-erigon-sequencer-001
```

## Table of Contents

- [acl mode](#acl-mode)
- [acl add](#acl-add)
- [acl remove](#acl-remove)
- [acl update](#acl-update)

## `acl mode`

```bash
$ acl mode --help
[cdk-erigon-lib] timestamp 2024-03-12:16:34
NAME:
   acl mode - Set the mode of the ACL

USAGE:
   acl mode [command options] [arguments...]

OPTIONS:
   --datadir value  Data directory for the databases (default: /home/erigon/.local/share/erigon)
   --mode value     Mode of the ACL (allowlist, blocklist or disabled)
   --help, -h       show help
```

The `acl mode` command sets the mode - allowlist, blocklist, or disabled within the network.

- `disabled`: access lists are disabled. All addresses will be able to send transactions.
- `allowlist`: allowlist is enabled. If address is not in the allowlist, it won't be able to send transactions (regular, contract deployment, or both).
- `blocklist`: blocklist is enabled. If address is in the blocklist, it won't be able to send transactions (regular, contract deployment, or both).

The above acl modes are all saved independently - changing the mode will save the existing list contents and the mode can be switched back and forth without resetting the list contents.

The command can be used as below. The `--datadir` path must point exactly to `<erigon_datadir>/txpool/acls`

```bash
acl mode --mode allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The above example will block all addresses from sending transactions.

```bash
$ export ETH_RPC_URL="$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"
$ private_key="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"

$ cast send --legacy --private-key "$private_key" --value 0.01ether --rpc-url "$ETH_RPC_URL" 0x0000000000000000000000000000000000000000
Error:
server returned an error response: error code -32000: RPC error response: INTERNAL_ERROR: sender disallowed to send tx by ACL policy

$ cast send --legacy --private-key "$private_key" --rpc-url "$ETH_RPC_URL" --create 604260005260206000F3
Error:
server returned an error response: error code -32000: RPC error response: INTERNAL_ERROR: sender disallowed to deploy contract by ACL policy
```

To disable the allowlist, one can use:

```bash
acl mode --mode disabled --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The allowlist will now be disabled and any address can send transactions.

```bash
$ cast send --legacy --private-key "$private_key" --value 0.01ether --rpc-url "$ETH_RPC_URL" 0x0000000000000000000000000000000000000000

blockHash               0xcd8aa8dba844f3f2fa96af7c02b45334c4029b2d0b8c38a24c713f933eca9257
blockNumber             222
contractAddress
cumulativeGasUsed       21000
effectiveGasPrice       1000000000
from                    0xE34aaF64b29273B7D567FCFc40544c014EEe9970
gasUsed                 21000
logs                    []
logsBloom               0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
root
status                  1 (success)
transactionHash         0x0d90c84a6757d25453971c3e5f4031e887bd7a58d9801e2e081153f1363bade0
transactionIndex        0
type                    0
blobGasPrice
blobGasUsed
authorizationList
to                      0x0000000000000000000000000000000000000000
```

## `acl add`

```bash
$ acl add --help
[cdk-erigon-lib] timestamp 2024-03-12:16:34
NAME:
   acl add - Add the ACL policy

USAGE:
   acl add [command options] [arguments...]

OPTIONS:
   --datadir value  Data directory for the databases (default: /home/erigon/.local/share/erigon)
   --address value  Address of the account to add the policy
   --policy value   Policy to add
   --type value     Type of the ACL (allowlist or blocklist) (default: allowlist)
   --help, -h       show help
```

Supported values for `--policy` are:

- `sendTx`: enables or disables ability of an account to send transactions (deploy contracts transactions not included).
- `deploy`: enables or disables ability of an account to deploy smart contracts (other transactions not included).

The `acl add` command will add new addresses with a specific policy to the acl. For example, when the `allowlist` type is active:

```bash
acl add --address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 --policy sendTx --type allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The command will include `0xE34aaF64b29273B7D567FCFc40544c014EEe9970` into the allowlist and this address will be able to send transactions while the allowlist mode is active.

## `acl remove`

```bash
$ acl remove --help
[cdk-erigon-lib] timestamp 2024-03-12:16:34
NAME:
   acl remove - Remove the ACL policy

USAGE:
   acl remove [command options] [arguments...]

OPTIONS:
   --datadir value  Data directory for the databases (default: /home/erigon/.local/share/erigon)
   --address value  Address of the account to remove the policy
   --policy value   Policy to remove
   --type value     Type of the ACL (allowlist or blocklist) (default: Allowlist)
   --help, -h       show help
```

Counterpart for `acl add`, but to remove an address from an acl.

```bash
acl remove --address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 --policy sendTx --type allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The above command will remove `0xE34aaF64b29273B7D567FCFc40544c014EEe9970` from the allowlist, this address will not able to send transactions.

## `acl update`

```bash
$ acl update --help
[cdk-erigon-lib] timestamp 2024-03-12:16:34
NAME:
   acl update - Update the ACL

USAGE:
   acl update [command options] [arguments...]

OPTIONS:
   --datadir value  Data directory for the databases (default: /home/erigon/.local/share/erigon)
   --csv value      CSV file with the ACL
   --type value     Type of the ACL (allowlist or blocklist) (default: Allowlist)
   --help, -h       show help
```

`acl update` takes a `.csv` file input to modify an acl according to the specified values within the `.csv` file. Essentially, this is `acl add` and/or `acl remove` in bulk. The contents of the `.csv` file is absolute and final - meaning it will overwrite all existing policies for all addresses in the `.csv` file.

The .csv file takes a form of:

```csv
0xE34aaF64b29273B7D567FCFc40544c014EEe9970,"sendTx,deploy"
0x53d284357ec70cE289D6D64134DfAc8E511c8a3D,"sendTx"
0xab7c74abc0c4d48d1bdad5dcb26153fc8780f83e,"deploy"
0xfe9e8709d3215310075d67e3ed32a380ccf451c8,"sendTx,deploy"
0x61edcdf5bb737adffe5043706e7c5bb1f1a56eea,"sendTx"
0x85b931a32a0725be14285b66f1a22178c672d69b,"deploy"
0x2a65aca4d5fc5b5c859090a6c34d164135398226,"sendTx,deploy"
0x6cc5f688a315f3dc28a7781717a9a798a59fda7b,"sendTx"
0xab5801a7d398351b8be11c439e05c5b3259aec9b,"deploy"
```

Using the `.csv` file as input:

```bash
acl update --csv acl_update.csv --type allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The above command will include the addresses and the respective policies to the allowlist.
