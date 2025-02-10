# Test Configuration Generator

The purpose of this tool is to automate the creation of comprehensive test suites for the CDK stack. By generating multiple combinations, it ensures that the stack is tested across various configurations and scenarios, helping to catch potential regressions.

The script combines configuration files from three categories:

- Fork configurations under `forks/` (e.g., fork9.yml, fork10.yml)
- Consensus modes under `consensus/` (e.g., rollup.yml, validium.yml)
- Component types under `components` (e.g., zkevm-node-sequencer-sequence-sender-aggregator.yml, erigon-sequencer-cdk-sequence-sender-aggregator.yml)

It then creates new `.yml` files that represent each unique combination of these configurations.

To run it, you can simply use: `./combine-ymls.sh`.

Here is an example:

```bash
$ ./combine-ymls.sh
Creating combinations...
- combinations/fork11-cdk-erigon-rollup.yml
- combinations/fork11-legacy-zkevm-rollup.yml
- combinations/fork11-cdk-erigon-validium.yml
- combinations/fork12-cdk-erigon-rollup.yml
- combinations/fork12-cdk-erigon-validium.yml
- combinations/fork13-cdk-erigon-rollup.yml
- combinations/fork13-cdk-erigon-validium.yml
- combinations/fork9-cdk-erigon-rollup.yml
- combinations/fork9-legacy-zkevm-rollup.yml
- combinations/fork9-cdk-erigon-validium.yml
- combinations/fork9-legacy-zkevm-validium.yml
All combinations created!
```

The generated test files are then utilized by the `deploy` job in the CI pipeline to tests the different combinations.
