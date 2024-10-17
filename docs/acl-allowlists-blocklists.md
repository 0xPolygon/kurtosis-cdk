# ACL - Allowlisting and Blocklisting Addresses in CDK

CDK offers ACLs which allow the network operator to enforce an allowlist and blocklist within the network.
ACL is a command that can be used within the Erigon sequencer. First, spin up a Kurtosis CDK environment.
The ACL must be setup within the Erigon sequencer, and the policies are applied on a network level. Individual RPCs setting up ACLs will have no effect on the network.

```
kurtosis service shell cdk cdk-erigon-sequencer-001
```

The command is built within Erigon by default:

```
$ acl --help
[cdk-erigon-lib] timestamp 2024-03-12:16:34
NAME:
   acl - A new cli application

USAGE:
   acl [command] [flags]

VERSION:
   2.43.0-dev-d9300660

COMMANDS:
   mode     Set the mode of the ACL
   update   Update the ACL
   remove   Remove the ACL policy
   add      Add the ACL policy
   help, h  Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --help, -h     show help
   --version, -v  print the version

```

## acl mode

```
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

The `acl mode` command sets the mode - allowlist, blokclist, or disabled within the network.

```
disabled - access lists are disabled. All addresses will be able to send transactions.
allowlist - allowlist is enabled. If address is not in the allowlist, it won't be able to send transactions (regular, contract deployment, or both).
blocklist - blocklist is enabled. If address is in the blocklist, it won't be able to send transactions (regular, contract deployment, or both).
```

The above acl modes are all saved independently - changing the mode will save the existing list contents and the mode can be switched back and forth without resetting the list contents.

The command can be used as below. The `--datadir` path must point exactly to `<erigon_datadir>/txpool/acls`

```
acl mode --mode allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The above example will block all addresses from sending transactions.

## acl add

```
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

```
sendTx - enables or disables ability of an account to send transactions (deploy contracts transactions not included).
deploy - enables or disables ability of an account to deploy smart contracts (other transactions not included).
```

The `acl add` command will add new addresses with a specific policy to the acl. For example, when the `allowlist` type is active:

```
acl add --address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 --policy sendTx --type allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The amount command will include `0xE34aaF64b29273B7D567FCFc40544c014EEe9970` into the allowlist and this address will be able to send transactions while the allowlist mode is active.

## acl remove

```
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

```
acl remove --address 0xE34aaF64b29273B7D567FCFc40544c014EEe9970 --policy sendTx --type allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The above command will remove `0xE34aaF64b29273B7D567FCFc40544c014EEe9970` from the allowlist to send transactions.

## acl update

```
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

`acl update` takes a .csv file input to modify an acl according to the specified values within the .csv file. Essentially, this is `acl add` and/or `acl remove` in bulk.
The contents of the .csv file is absolute and final - meaning it will overwrite all existing policies for all addresses in the .csv file.

The .csv file takes a form of:
```
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

Using the .csv file as input:

```
acl update --csv <acl_update.csv> --type allowlist --datadir /home/erigon/data/dynamic-kurtosis-sequencer/txpool/acls
```

The above command will include the addresses and the respective policies to the allowlist.