# Regenesis tool guide
The first part of this guide shows how to run and compile the tool locally.

Repo: `github.com/ARR552/regenesisTool`

1. Clone the repo: 
```
git clone git@github.com:ARR552/regenesisTool.git
cd regenesisTool
git clone https://github.com/0xPolygonHermez/cdk-erigon.git
cd cdk-erigon
git checkout ba0a89e58fd013e637fc3532492
cd ..
```
2. Download the erigon DB backup or sync the cdk-erigon node.
For zkevm mainnet and cardona, backups can be found here:
```
https://storage.googleapis.com/zkevm-testnet-snapshots/zkevm-testnet-erigon-snapshot.tgz
https://storage.googleapis.com/zkevm-mainnet-snapshots/zkevm-mainnet-erigon-snapshot.tgz
```
Uncompress the backup: `tar -xzvf zkevm-mainnet-erigon-snapshot.tgz`
3. Run the next commands:
```
go run main.go --action=regenesis --chaindata="<PathToFolder>/zkevm-mainnet-erigon-snapshot/chaindata" --output=./
```

**Notes:** minimum RAM 32GB for zkevm mainnet and cardona

## Kurtosis guide:
This second part of the guide shows how to create the regenesis file for an specific kurtosis environment.
1. Stop the sequecer or avoid any activity in the network:
```
kurtosis service exec cdk cdk-erigon-sequencer-001 "pkill -SIGTRAP "proc-runner.sh"" || true
```
2. Copy the DB files to localhost. Take into account that the container name can be different for each kurtosis deployment(`cdk-erigon-sequencer-001--b20adbeed8f8443281bd494798ef60fd`):
```
docker cp cdk-erigon-sequencer-001--b20adbeed8f8443281bd494798ef60fd:/home/erigon/data/dynamic-kurtosis-sequencer/chaindata/mdbx.dat .
```
3. Download the regenesisTool binary and give it execution permissions:
```
wget https://github.com/ARR552/regenesisTool/releases/download/v0.0.1/regenesisTool
chmod +x regenesisTool
```
4. Run the tool to build the genesis file:
```
./regenesisTool --action=regenesis --chaindata="./"  --output=./
```