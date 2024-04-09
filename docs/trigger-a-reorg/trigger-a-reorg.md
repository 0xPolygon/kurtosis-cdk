# Trigger a Reorg

Blockchain networks rely on a consensus mechanism to agree on the valid state of the blockchain. This mechanism ensures that all participants in the network reach an agreement on the order and validity of transactions. Occasionally, multiple blocks are mined and added to the blockchain at approximately the same time. When this happens, the blockchain temporarily forks into two or more branches. This is known as a fork in the blockchain. A blockchain reorganisation (or reorg) occurs when one branch of the blockchain fork becomes longer than the others due to the addition of more blocks. The network then considers this longer branch as the valid chain and reorganizes the blockchain to follow it.

For the purpose of this example, we will explain how to trigger a blockchain reorg at the L1 level.

## Deploy a Local L1 Chain

First, clean up your environment.

```bash
kurtosis clean --all
```

Let's deploy the L1 chain with three validators.

```bash
patch -p1 < docs/trigger-a-reorg/reorg.patch
kurtosis run --enclave l1 --args-file params.yml --main-file ethereum.star .
```

Set up handy aliases for the RPC URLs.

```bash
rpc1="http://$(kurtosis port print l1 el-1-geth-lighthouse rpc)"
rpc2="http://$(kurtosis port print l1 el-2-geth-lighthouse rpc)"
rpc3="http://$(kurtosis port print l1 el-3-geth-lighthouse rpc)"
rpcs=("$rpc1" "$rpc2" "$rpc3")
```

Send a few transactions to the network.

```bash
polycli loadtest --rpc-url $rpc1 --requests 100 --rate-limit 100 --mode t --verbosity 700
```

Get the block number and state root hash of the last block. Each node should have the same values, meaning the nodes are in sync.

```bash
for rpc_url in "${rpcs[@]}"; do
  block_number="$(cast block-number --rpc-url "$rpc_url")"
  block_state_root="$(cast block --rpc-url "$rpc_url" --json | jq -r .stateRoot)"
done
```

Get the metrics related to chain reorganisations.

```bash
curl --silent "http://$(kurtosis port print l1 el-1-geth-lighthouse metrics)/debug/metrics/prometheus" | grep "chain_reorg"
```

Or directly from the container.

```bash
docker run -it --net=container:$(docker ps | grep el-1-geth-lighthouse | awk '{printf $1}') --privileged nicolaka/netshoot:latest /bin/bash
curl --silent 0.0.0.0:9001/debug/metrics/prometheus | grep "chain_reorg"
```

It should output that no reorgs have happened yet.

```bash
# TYPE chain_reorg_add gauge
chain_reorg_add 0
# TYPE chain_reorg_drop gauge
chain_reorg_drop 0
# TYPE chain_reorg_executes gauge
chain_reorg_executes 0
```

## Introduce Network Latencies

Start a shell in the first execution node service. It should be called `el-1-geth-lighthouse`.

```bash
docker run -it --net=container:$(docker ps | grep el-1-geth-lighthouse | awk '{printf $1}') --privileged nicolaka/netshoot:latest /bin/bash
```

Ping the other execution nodes. Everything should be fine.

```bash
ping -c 4 el-2-geth-lighthouse
```

Now, let's introduce network latencies. For the sake of this example, we will introduce a delay of five seconds.

```bash
tc qdisc add dev eth0 root netem delay 5000ms
```

You can verify that the delay has been applied.

```bash
tc -s qdisc
```

Now send a few packets again. You should see that they have been delayed by five seconds.

```bash
ping -c 4 el-2-geth-lighthouse
```

We isolated the first execution node from the rest of the network. Since execution nodes are responsible for mining new blocks and gossiping transactions, this node will fall behind the other execution nodes.

We are now ready to trigger a chain reorg!

## Trigger a Chain Reorg

Send lots of transactions to the second RPC.

```bash
polycli loadtest --rpc-url $rpc2 --requests 10000 --rate-limit 10000 --mode t --verbosity 700 --send-only
```

After some time, watch the first node get out of sync with the rest of the other nodes.

```bash
for rpc_url in "${rpcs[@]}"; do
  cast block-number --rpc-url "$rpc_url"
  cast block --rpc-url "$rpc_url" --json | jq -r .stateRoot
done
```

```bash
39
0x5d82f4809b30b0a4b1b68da1575076aa96725f0cbd57fb34f25fdbd894ee9abc
52
0x81ac766a2b0445e8aaf7550be627704adbc63eb2bfc18e9329c5940dc740e537
52
0x81ac766a2b0445e8aaf7550be627704adbc63eb2bfc18e9329c5940dc740e537
```

Then connect to the first node and send a few transactions.

We send the transactions directly from inside the execution node service because of the network latencies.

```bash
docker build --file docs/trigger-a-reorg/network-helper.Dockerfile --tag network-helper .
docker run -it --net=container:$(docker ps | grep el-2-geth-lighthouse | awk '{printf $1}') --privileged leovct/network-helper:latest /bin/bash
d70d9ede9c5f:~# polycli loadtest --rpc-url http://0.0.0.0:8545 --requests 100 --rate-limit 100 --verbosity 700
```

The first node is now on a different fork from the other three nodes.

Let's trigger a chain reorg.

Remove the latency on the first node.

```bash
d70d9ede9c5f:~# tc qdisc del dev eth0 root netem
```

After some time you should see that the first node catches up with the rest of the chain. It reorged!

You can check the metrics to see how many blocks were reorged.

```bash
$ curl --silent "http://$(kurtosis port print l1 el-1-geth-lighthouse metrics)/debug/metrics/prometheus" | grep "chain_reorg"
# TYPE chain_reorg_add gauge
chain_reorg_add 24
# TYPE chain_reorg_drop gauge
chain_reorg_drop 0
# TYPE chain_reorg_executes gauge
chain_reorg_executes 0
```

## Reorg a block including a zkEVM bridge deposit

TODO
