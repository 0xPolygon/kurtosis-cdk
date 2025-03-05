# Trustless recovery from DAC and L1

In cases where the L2 state is lost, the Erigon sequencer is capable of recovering from the DAC and L1 blocks. Only the sequencer is capable of doing this, and other Erigon RPCs only sync from the datastream.
Within the Erigon config, there is [zkevm.l1-sync-start-block](https://github.com/0xPolygon/kurtosis-cdk/blob/1403ea6035f1ae0061d40da973ac0002f1b7691b/templates/cdk-erigon/config.yml#L401-L405) and [zkevm.da-url](https://github.com/0xPolygon/kurtosis-cdk/blob/1403ea6035f1ae0061d40da973ac0002f1b7691b/templates/cdk-erigon/config.yml#L159-L164) parameters which allow the recovery.

## Testing in Kurtosis CDK

First, spin up a Kurtosis CDK devnet. To simulate L2 data loss, remove the `--datadir` folder from the sequencer.

```
kurtosis service exec cdk cdk-erigon-sequencer-001 "rm -rf ~/data/dynamic-kurtosis-sequencer"
```

Then immediately follow up by stopping the cdk-erigon-rpc-001 and cdk-node-001 services.

```
kurtosis service stop cdk cdk-erigon-rpc-001
kurtosis service stop cdk cdk-node-001
```

Change the sequencer's `config.yaml` file using root permission. Under normal circumstances, `kurtosis exec` would've been used for consistency, but the sequencer's image disables root permission, so `docker exec` with the `-u root` has been used to get permission to make config file changes.

```
docker exec -it -u root $(docker ps -aqf "name=cdk-erigon-sequencer-001") sh -c "sed -i 's/zkevm.l1-sync-start-block: 0/zkevm.l1-sync-start-block: 1/' /etc/cdk-erigon/config.yaml"
docker exec -it -u root $(docker ps -aqf "name=cdk-erigon-sequencer-001") sh -c "sed -i 's/zkevm.da-url: \"\"/zkevm.da-url: http:\/\/zkevm-dac-001:8484/' /etc/cdk-erigon/config.yaml"
```

Restart the sequencer

```
kurtosis service stop cdk cdk-erigon-sequencer-001
kurtosis service start cdk cdk-erigon-sequencer-001
```

The resync is expected to take some time, which is dependent on the `zkevm.l1-sync-start-block` value. The sequencer will sync from the configured start block number to the latest block number.
Since this is a local devnet, the L1 block height is not expected to be too high, so `1` has been used. Do not use this for production or even testnet environments.

Monitor the sequencer's logs

```
kurtosis service logs cdk cdk-erigon-sequencer-001
```

Once there is a log indicating the sync recovery has completed, we can now revert the configurations. The below environment where L1 blockheight was `8988` and batch was `381` took about 6 minutes to complete.

```
[cdk-erigon-sequencer-001] [INFO] [10-17|04:50:06.855] L1 block sync recovery has completed!    batch=381
```

Now revert the sequencer's `config.yaml` file to start sequencing again:

```
docker exec -it -u root $(docker ps -aqf "name=cdk-erigon-sequencer-001") sh -c "sed -i 's/zkevm.l1-sync-start-block: 1/zkevm.l1-sync-start-block: 0/' /etc/cdk-erigon/config.yaml"
docker exec -it -u root $(docker ps -aqf "name=cdk-erigon-sequencer-001") sh -c "sed -i 's/zkevm.da-url: http:\/\/zkevm-dac-001:8484/zkevm.da-url: \"\"/' /etc/cdk-erigon/config.yaml"
```

Restart the sequencer

```
kurtosis service stop cdk cdk-erigon-sequencer-001
kurtosis service start cdk cdk-erigon-sequencer-001
```

Then restart the other stopped CDK components

```
kurtosis service start cdk cdk-erigon-rpc-001
kurtosis service start cdk cdk-node-001
```

Monitor the logs to make sure the network is functional again.
