# Resequencing batches with the Erigon sequencer

In the case of the sequencer receiving "bad" batches, which are effectively unprovable, it is possible to resequence.
The attached [script](./test_resequence.sh) provides an automation to test this kind of scenario. Please refer to the script for quick testing.

In cases where you'd want to manually trigger such cases, refer to the below steps:

The high level steps to resequence in the provided script is:

1. Stop sequencer
2. Change configs to simulate bad batches
3. Start sequencer with modified config
4. Inject load
5. Wait for batches to virtualize
6. Stop cdk-node-001
7. Stop sequencer
8. Rollback batches on L1 contract
9. Unwind to batch in sequencer with `integration` command
10. Change sequencer config to resequence
11. Start sequencer
12. Once resequencing is done/timed out, stop the sequencer
13. Change to normal config and restart sequencer
14. Start cdk-node-001
15. Compare block hashes from sequencer and erigon rpc

Assuming that you encountered bad batches, or want to resequence for some reason, we can reference the steps above:

#### Make backup of the configs

```bash
kurtosis service exec cdk  cdk-erigon-sequencer-001 "cp \-r /etc/cdk-erigon/ /tmp/"
```

#### Stop the cdk-node

It is important to stop the cdk-node-001 service when attempting this procedure.

```bash
kurtosis service stop cdk cdk-node-001
```

#### Stop the sequencer

The Erigon sequencer image in Kurtosis CDK is setup so that the `cdk-erigon` process can be killed without exiting the container. This allows changing the configuration of the sequencer more easily.

```bash
# Send a SIGTRAP signal to the proc-runner process
kurtosis service exec cdk cdk-erigon-sequencer-001 "pkill -SIGTRAP "proc-runner.sh"" || true
# Send a SIGINT signal to the cdk-erigon process
kurtosis service exec cdk cdk-erigon-sequencer-001 "pkill -SIGINT "cdk-erigon"" || true
```

#### Getting the latest L1 verified batch

This can usually be done by querying the L1 explorer, but in a Kurtosis devnet environment, this can be done by querying the rollup manager contract.

```bash
# Queries the latest verified batch number
current_batch=$(cast logs --rpc-url "$(kurtosis port print cdk el-1-geth-lighthouse rpc)" --address 0x1Fe038B54aeBf558638CA51C91bC8cCa06609e91 --from-block 0 --json | jq -r '.[] | select(.topics[0] == "0x9c72852172521097ba7e1482e6b44b351323df0155f97f4ea18fcec28e1f5966" or .topics[0] == "0xd1ec3a1216f08b6eff72e169ceb548b782db18a6614852618d86bb19f3f9b0d3") | .topics[1]' | tail -n 1 | sed 's/^0x//')

# Converts hexadecimal value
current_batch_dec=$((16#$current_batch))
```

- `0x1Fe038B54aeBf558638CA51C91bC8cCa06609e91` is the address of our particular rollup contract.
- FilterVerifyBatches is a free log retrieval operation binding the contract event `0x9c72852172521097ba7e1482e6b44b351323df0155f97f4ea18fcec28e1f5966` for Validium Etrog networks.
- `0xd1ec3a1216f08b6eff72e169ceb548b782db18a6614852618d86bb19f3f9b0d3` is the verification topic for Etrog networks.

#### Rollback batches on L1 contract

Since the CDK network is managed by the L1 rollup manager contract, its important to trigger a batch rollback on the L1 rollup manager contract for our particular network after the L2 network is stopped.

```bash
cast send "0x6c6c009cC348976dB4A908c92B24433d4F6edA43" "rollbackBatches(address,uint64)" "0x1Fe038B54aeBf558638CA51C91bC8cCa06609e91" "$latest_verified_batch" --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" --rpc-url "$(kurtosis port print cdk el-1-geth-lighthouse rpc)"
```

- `0x6c6c009cC348976dB4A908c92B24433d4F6edA43` is the address of the rollup manager contract on L1
- `0x1Fe038B54aeBf558638CA51C91bC8cCa06609e91` is the address of our particular rollup contract.
- `0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625` is the private key of the admin address.

#### Unwind batches in the sequencer using `integration` command

The erigon sequencer image used in Kurtosis CDK comes with a built-in `integration` command line tool.

```bash
$ integration --help
[cdk-erigon-lib] timestamp 2024-03-12:16:34
long and heavy integration tests for Erigon

Usage:
  integration [command]

Available Commands:
  compare_bucket       compare bucket to the same bucket in '--chaindata.reference'
  compare_states       compare state buckets to buckets in '--chaindata.reference'
  completion           Generate the autocompletion script for the specified shell
  f_to_mdbx            copy data from '--chaindata' to '--chaindata.to'
  force_set_history_v3 Override existing --history.v3 flag value (if you know what you are doing)
  force_set_prune      Override existing --prune flag value (if you know what you are doing)
  force_set_snapshot   Override existing --snapshots flag value (if you know what you are doing)
  help                 Help about any command
  loop_exec
  loop_ih
  mdbx_to_mdbx         copy data from '--chaindata' to '--chaindata.to'
  print_migrations
  print_stages
  read_domains         Run block execution and commitment with Domains.
  remove_migration
  reset_state          Reset StateStages (5,6,7,8,9,10) and buckets
  run_migrations
  stage_bodies
  stage_call_traces
  stage_exec
  stage_hash_state
  stage_headers
  stage_history
  stage_log_index
  stage_senders
  stage_snapshots
  stage_trie
  stage_tx_lookup
  state_domains        Run block execution and commitment with Domains.
  state_stages         Run all StateStages (which happen after senders) in loop.
Examples:
--unwind=1 --unwind.every=10  # 10 blocks forward, 1 block back, 10 blocks forward, ...
--unwind=10 --unwind.every=1  # 1 block forward, 10 blocks back, 1 blocks forward, ...
--unwind=10  # 10 blocks back, then stop
--integrity.fast=false --integrity.slow=false # Performs DB integrity checks each step. You can disable slow or fast checks.
--block # Stop at exact blocks
--chaindata.reference # When finish all cycles, does comparison to this db file.

  state_stages_zkevm   Run all StateStages in loop.
Examples:
state_stages_zkevm --datadir=/datadirs/hermez-mainnet--unwind-batch-no=10  # unwind so the tip is the highest block in batch number 10
state_stages_zkevm --datadir=/datadirs/hermez-mainnet --unwind-batch-no=2 --chain=hermez-bali --log.console.verbosity=4 --datadir-compare=/datadirs/pre-synced-block-100 # unwind to batch 2 and compare with another datadir

  warmup

Flags:
  -h, --help                           help for integration
      --log.console.json               Format console logs with JSON
      --log.console.verbosity string   Set the log level for console logs (default "info")
      --log.dir.json                   Format file logs with JSON
      --log.dir.path string            Path to store user and error logs to disk
      --log.dir.verbosity string       Set the log verbosity for logs stored to disk (default "info")
      --log.json                       Format console logs with JSON
      --metrics                        Enable metrics collection and reporting
      --metrics.addr string            Enable stand-alone metrics HTTP server listening interface (default "127.0.0.1")
      --metrics.port int               Metrics HTTP server listening port (default 6060)
      --pprof                          Enable the pprof HTTP server
      --pprof.addr string              pprof HTTP server listening interface (default "127.0.0.1")
      --pprof.cpuprofile string        Write CPU profile to the given file
      --pprof.port int                 pprof HTTP server listening port (default 6060)
      --trace string                   Write execution trace to the given file
      --verbosity string               Set the log level for console logs (default "info")

Use "integration [command] --help" for more information about a command.

```

Using the `integration` command, we can unwind batches to the latest verified batch.

```bash
kurtosis service exec cdk cdk-erigon-sequencer-001 "integration state_stages_zkevm --config=/etc/cdk-erigon/config.yaml --unwind-batch-no=$latest_verified_batch --chain dynamic-kurtosis --datadir /home/erigon/data/dynamic-kurtosis-sequencer"
```

#### Change sequencer config to resequence with timeout enabled

```bash
kurtosis service exec cdk cdk-erigon-sequencer-001 "timeout 300s cdk-erigon --pprof=true --pprof.addr 0.0.0.0 --config /etc/cdk-erigon/config.yaml --datadir /home/erigon/data/dynamic-kurtosis-sequencer  --zkevm.sequencer-resequence-strict=false --zkevm.sequencer-resequence=true --zkevm.sequencer-resequence-reuse-l1-info-index=true"
```

After the above is done, stop the sequencer again.

```bash
# Send a SIGTRAP signal to the proc-runner process
kurtosis service exec cdk cdk-erigon-sequencer-001 "pkill -SIGTRAP "proc-runner.sh"" || true
# Send a SIGINT signal to the cdk-erigon process
kurtosis service exec cdk cdk-erigon-sequencer-001 "pkill -SIGINT "cdk-erigon"" || true
```

#### Restart the cdk-node

```bash
kurtosis service start cdk cdk-node-001
```

#### Monitor logs and check blocks

The resequencing should be complete. Monitor the logs for the CDK components:

- Check the latest block number and arbitrary block hashes from the sequencer
- Check the latest block number and arbitrary block hashes from the erigon rpc and compare
- Check that the L1 verified batch number increments after some time
