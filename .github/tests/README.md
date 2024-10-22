# Test Configuration Generator

The purpose of this tool is to automate the creation of comprehensive test suites for the CDK stack. By generating multiple combinations, it ensures that the stack is tested across various configurations and scenarios, helping to catch potential regressions.

The script combines configuration files from three categories:

- Fork configurations under `forks/` (e.g., fork9.yml, fork10.yml)
- Data availability modes under `da-modes/` (e.g., rollup.yml, cdk-validium.yml)
- Component types under `components` (e.g., zkevm-node-sequencer-sequence-sender-aggregator.yml, erigon-sequencer-cdk-sequence-sender-aggregator.yml)

It then creates new `.yml` files that represent each unique combination of these configurations.

To run it, you can simply use: `./combine-ymls.sh`.

Here is an example:

```bash
$ ./combine-ymls.sh
Creating combinations...
- combinations/fork11-new-cdk-stack-cdk-validium.yml
- combinations/fork11-legacy-zkevm-stack-rollup.yml
- combinations/fork11-new-cdk-stack-rollup.yml
- combinations/fork12-new-cdk-stack-cdk-validium.yml
- combinations/fork12-new-cdk-stack-rollup.yml
- combinations/fork9-legacy-zkevm-stack-cdk-validium.yml
- combinations/fork9-new-cdk-stack-cdk-validium.yml
- combinations/fork9-legacy-zkevm-stack-rollup.yml
- combinations/fork9-new-cdk-stack-rollup.yml
All combinations created!
```

The generated test files are then utilized by the `deploy` job in the CI pipeline to tests the different combinations.
