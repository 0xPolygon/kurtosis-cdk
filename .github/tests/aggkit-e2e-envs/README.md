# aggkit-e2e env presets

Reproducible `kurtosis run --args-file` presets for the aggkit e2e target
environments. Each preset is derived **faithfully** from the aggkit CI
`read-aggkit-args` compositions in
`agglayer/aggkit/.github/workflows/test-e2e.yml` (the `put_args` deep-merge,
`jq -s 'reduce .[] as $item ({}; . * $item)'`, last-file-wins). They exist so
the per-env snapshots (plan steps P7–P10) are regenerable from
version-controlled inputs.

Every preset is **snapshot-clean**: no `bridge_spammer` and no other
settlement-inducing `additional_services` entry, satisfying the P3
`snapshot/snapshot.md` "no settlement before snapshot" prerequisite.

## How `main.star` handles topology

`main.star` deploys exactly **one L2 per `kurtosis run`**. The legacy aggkit
multi-chain CI brings up N chains by running each per-chain args-file
*sequentially into the SAME enclave* (see
`agglayer/e2e/.github/workflows/aggkit-e2e-multi-chains.yml`: it `tee`s each
`kurtosis-cdk-args-{1,2,3}` into a JSON file and runs
`kurtosis run --enclave <name> --args-file ...` once per chain). The first
chain deploys the shared L1 + agglayer; subsequent chains set
`deploy_l1: false` / `deploy_agglayer: false` to reuse them.

Accordingly:

- **Single-chain envs** (`op-fep`, `op-fep-committee`) are single-document
  YAML files.
- **Multi-chain envs** (`op-pp-2chains`, `cdk-erigon-3chains`) are
  **multi-document** YAML files: each `---` document is a standalone
  single-chain args-file, to be applied **in order** into one shared enclave.
  Split with `yq` (or python) before running — see each invocation below.

## Presets

| Preset | Topology | aggkit source JSONs (merge order) | snapshot `chain_type` (P3) |
| --- | --- | --- | --- |
| `op-fep.yml` | 1 OP-succinct L2 (001), FEP, op-succinct **mock prover**, agglayer | `test_e2e_op_args_base.json` → `test_e2e_op_succinct_args_base.json` → `test_e2e_single_chain_op_succinct_args.json` (CI `op_succinct_args`) | `op-stack` |
| `op-fep-committee.yml` | 1 OP-succinct L2 (001), FEP, mock prover + AggOracle committee (quorum 2/3) | `test_e2e_op_args_base.json` → `test_e2e_op_succinct_args_base.json` → `test_e2e_single_chain_op_succinct_aggoracle_committee_args.json` (CI `op_succinct_aggoracle_committee_args`) | `op-stack` |
| `op-pp-2chains.yml` | 2 OP "pessimistic" (ecdsa-multisig) L2s (001, 002) sharing one L1+agglayer | doc1 (001): `test_e2e_op_args_base.json` → `test_e2e_op_args_chain_1.json` (CI `kurtosis-cdk-args-1`); doc2 (002): `test_e2e_op_args_base.json` → `test_e2e_op_args_chain_2.json` (CI `kurtosis-cdk-args-2`) | `op-stack` |
| `cdk-erigon-3chains.yml` | 3 cdk-erigon (ecdsa-multisig) L2s (001, 002, 003) sharing one L1+agglayer | doc1 (001): base → `test_e2e_cdk_erigon_custom_gas_token.json` (CI `kurtosis-cdk-args-3`); doc2 (002): base → `test_e2e_cdk_erigon_multi_chains_args_2.json` → `test_e2e_cdk_erigon_custom_gas_token.json` (CI `kurtosis-cdk-args-4`); doc3 (003): base → `test_e2e_cdk_erigon_multi_chains_args_3.json` (CI `kurtosis-cdk-args-5`) | `cdk-erigon` |

(base = `test_e2e_cdk_erigon_args_base.json`.)

## Deliberate deviations from the aggkit source compositions

1. **Drop `bridge_spammer`** (`op-fep.yml`, `op-fep-committee.yml`). The
   shared `test_e2e_op_succinct_args_base.json` sets
   `additional_services: ["bridge_spammer"]`; bridge_spammer submits bridge
   transactions before a snapshot would be taken, breaking the snapshot-clean
   prerequisite. Both FEP presets set `additional_services: []`. (The op-pp
   and cdk-erigon source compositions already use `additional_services: []`,
   so no change was needed there.)
2. **Custom gas token on chains 001 AND 002 for `cdk-erigon-3chains`** (003
   stays native). This mirrors the legacy CI exactly: args-3 = base +
   custom-gas (001), args-4 = base + multi-2 + custom-gas (002), args-5 =
   base + multi-3 (003). It is **not** a single custom-gas chain.

## `kurtosis run --args-file` invocations

### op-fep
```
kurtosis run --enclave op-fep \
  --args-file .github/tests/aggkit-e2e-envs/op-fep.yml .
```

### op-fep-committee
```
kurtosis run --enclave op-fep-committee \
  --args-file .github/tests/aggkit-e2e-envs/op-fep-committee.yml .
```

### op-pp-2chains (apply both docs IN ORDER to one enclave)
```
yq 'select(documents() == 0)' .github/tests/aggkit-e2e-envs/op-pp-2chains.yml > /tmp/op-pp-1.yml
yq 'select(documents() == 1)' .github/tests/aggkit-e2e-envs/op-pp-2chains.yml > /tmp/op-pp-2.yml
kurtosis run --enclave op-pp --args-file /tmp/op-pp-1.yml .
kurtosis run --enclave op-pp --args-file /tmp/op-pp-2.yml .
```

### cdk-erigon-3chains (apply all three docs IN ORDER to one enclave)
```
yq 'select(documents() == 0)' .github/tests/aggkit-e2e-envs/cdk-erigon-3chains.yml > /tmp/cdk-1.yml
yq 'select(documents() == 1)' .github/tests/aggkit-e2e-envs/cdk-erigon-3chains.yml > /tmp/cdk-2.yml
yq 'select(documents() == 2)' .github/tests/aggkit-e2e-envs/cdk-erigon-3chains.yml > /tmp/cdk-3.yml
kurtosis run --enclave cdk-erigon --args-file /tmp/cdk-1.yml .
kurtosis run --enclave cdk-erigon --args-file /tmp/cdk-2.yml .
kurtosis run --enclave cdk-erigon --args-file /tmp/cdk-3.yml .
```

> Without `yq`, split with python instead, e.g.:
> `python3 -c "import yaml,json,sys; print(json.dumps(list(yaml.safe_load_all(open(sys.argv[1])))[int(sys.argv[2])]))" <file> <doc-index> > /tmp/doc.json`

## `aggkit:local` image

The presets reference `aggkit_image: aggkit:local` (verbatim from the aggkit
CI), which expects a locally-built aggkit image tagged `aggkit:local`. The
aggkit CI builds it in the `build-aggkit-image` job. Build/load it before a
live run (or override `--args 'aggkit_image=<tag>'`).
