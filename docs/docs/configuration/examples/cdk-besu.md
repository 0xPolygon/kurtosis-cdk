---
sidebar_position: 3
---

# CDK Besu

These configurations run the L2 on a vanilla [Hyperledger Besu](https://github.com/hyperledger/besu) chain, with no CDK-specific or OP-specific execution client. Besu is connected to Agglayer exactly like any other sovereign chain: the bridge and global exit root contracts are predeployed in its genesis, the chain is registered on L1 as a sovereign rollup, and [AggKit](https://github.com/agglayer/aggkit) drives certificates and global exit root injection.

## Sovereign

The chain is a single-validator [QBFT](https://besu.hyperledger.org/private-networks/how-to/configure/consensus/qbft) network: one node is both the block proposer and the RPC endpoint. QBFT finalises every block as it is produced.

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/reth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- L2 Besu blockchain (single QBFT validator) with the sovereign bridge and global exit root contracts predeployed in genesis, enhanced with [AggKit](https://github.com/agglayer/aggkit) for Agglayer connectivity.
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.

#### Best For

- Validating that Agglayer's pessimistic proof path works against an unmodified, non-CDK execution client.
- Testing chain integrations that cannot adopt cdk-erigon or the OP stack.

#### Deployment

```bash
kurtosis run --enclave cdk --args-file .github/tests/besu/sovereign-ecdsa-multisig.yml .
```

#### Configuration

The QBFT validator is derived from `besu_validator_private_key`, and its address is encoded into the genesis `extraData` at deploy time, so the chain is reproducible from that key alone. Block cadence and gas limit are set with `besu_block_period_seconds`, `besu_epoch_length`, `besu_request_timeout_seconds` and `besu_gas_limit`.

:::info
Only `consensus_contract_type: ecdsa-multisig` is supported, and the deployment fails early if anything else is selected. Besu produces no validity proof, so FEP does not apply. The older `pessimistic` consensus contract is excluded for a version reason: it has to be pinned to aggkit 0.5.4, and aggkit only began reading block hashes from the JSON-RPC response in 0.9 ([agglayer/aggkit#1397](https://github.com/agglayer/aggkit/pull/1397)). Before that it recomputed them with go-ethereum's RLP header hashing, which never matches a QBFT block hash because QBFT strips the committed seals from `extraData` first — so the L2 bridge syncer silently drops every block carrying events and no certificate is ever built. The aggsender still runs in `PessimisticProof` mode on `ecdsa-multisig`.
:::

:::warning
The chain runs with a zero base fee and accepts zero-priced transactions. Because QBFT has instant finality, Besu serves no `safe` or `finalized` block tags — components that follow the chain head are configured to track `latest`.
:::
