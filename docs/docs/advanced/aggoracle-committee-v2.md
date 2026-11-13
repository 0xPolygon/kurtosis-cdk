# AggOracle Committee v2

The AggOracle injects the Global Exit Roots (GER) of L1 into the L2. With the **AggOracleCommittee v2** it doesn't send the GER itself: it asks a set of **GER validators** to sign it, and it injects it with a single transaction that carries the signatures of a threshold of them. The validators don't depend on the L2, and they never send transactions.

:::warning
The AggOracleCommittee v2 **replaces** the v1 in the same contract (`AggOracleCommittee.sol`), and the aggkit versions with the v2 don't support the v1 ([agglayer/aggkit#1943](https://github.com/agglayer/aggkit/pull/1943)). The v1 is still available here (`use_agg_oracle_committee`), for the images that have it. The two can't be enabled together.
:::

## What you need

The v2 needs three images that are not released yet. Until they are, this package has no default for any of them: set them in the arguments file.

| Argument | Image |
|---|---|
| `agglayer_contracts_image` | [agglayer-contracts](https://github.com/agglayer/agglayer-contracts) with the AggOracleCommittee v2 ([v13.0.0-rc.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v13.0.0-rc.0) or later) |
| `aggkit_image` | [aggkit](https://github.com/agglayer/aggkit) with `AggOracle.Mode = "committee"` ([agglayer/aggkit#1943](https://github.com/agglayer/aggkit/pull/1943)) |
| `ger_validator_signer_image` | The GER validator, `tools/ger_validator_signer` in aggkit |

It is only supported for the sovereign chains of the OP Stack (not for CDK-Erigon nor for Besu).

## Enabling it

```yaml
args:
  sequencer_type: op-reth
  consensus_contract_type: ecdsa-multisig

  use_agg_oracle_committee_v2: true
  agg_oracle_committee_threshold: 2
  agg_oracle_committee_total_validators: 3

  agglayer_contracts_image: <image>
  aggkit_image: <image>
  ger_validator_signer_image: <image>
```

An example is in [`.github/tests/other/aggoracle-committee-v2/op-reth.yml`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/.github/tests/other/aggoracle-committee-v2/op-reth.yml). It is not part of the CI matrix because of the images.

| Argument | Default | Description |
|---|---|---|
| `use_agg_oracle_committee_v2` | `false` | Deploy the AggOracleCommittee v2 and the GER validators |
| `agg_oracle_committee_threshold` | `0` | Signatures that the committee requires to inject a GER, from 1 to the number of validators |
| `agg_oracle_committee_total_validators` | `0` | Number of GER validators, from 1 to 255 |
| `ger_validator_signer_image` | _(none)_ | Image of the GER validators. It must be set |
| `ger_validator_signer_port` | `8080` | Port of the REST API of the validators |
| `ger_validator_block_finality` | `FinalizedBlock` | How final the L1 block that inserted a GER has to be for a validator to sign it, as aggkit writes it: `LatestBlock`, `SafeBlock` or `FinalizedBlock`, with an optional negative offset (`LatestBlock/-12` is the head minus 12 blocks) |

## What is deployed

- **The committee**, in the genesis of the L2 (the `createSovereignGenesis` tool of agglayer-contracts). It is the `globalExitRootUpdater` of the L2 GER manager. Its owner is the sovereign admin, its **proposer** is the account of the AggOracle (`l2_aggoracle_address`: the only one that can inject), and its validators are the ones described below.
- **One service per validator**, `ger-validator<deployment_suffix>-00<N>` (for example `ger-validator-001-001`), with its own configuration and keystore. They are deployed before aggkit. A validator signs a GER only if it is in the `AgglayerGER` contract of L1 and the block that inserted it is canonical and final for its own finality.
- **aggkit** with `Mode = "committee"`. The URL of every validator is registered in the committee, so aggkit reads it from the contract. There is a single AggOracle for the chain, unlike the v1, that needs one for every member.

The keys of the validators come from the same L2 mnemonic as the rest of the accounts, with the indexes 201 and following (see [Key Usage](./key-usage.md)). Their addresses are registered in the committee when the L2 genesis is created, and the keystores are created by the `contracts` service.

## Checking it

- The log of aggkit tells the mode that it chose, with a line like `AggOracle mode: aggoracle_committee_v2`.
- Every validator answers `GET /v1/info` with the address that it signs with, that must be one of the validators of the committee.
- If the AggOracle doesn't inject, the validators say why in their logs and in the code of their answers (`GER_NOT_FINAL` is normal until the L1 block is final).
