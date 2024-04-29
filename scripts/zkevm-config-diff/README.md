# zkEVM/CDK Config Diff Tool

A simple tool to compare our kurtosis-cdk configurations with the default ones and list any missing or unnecessary fields.

## Usage

1. Deploy the CDK stack using [kurtosis-cdk](https://github.com/0xPolygon/kurtosis-cdk).

2. Create folders to hold zkevm default and kurtosis-cdk configuration files.

```bash
mkdir -p default-configs kurtosis-cdk-configs
```

Or clean those folders if they are not empty.

```bash
rm -rf ./default-configs/* ./kurtosis-cdk-configs/*
```

3. Dump default configurations.

```bash
./zkevm_config.sh dump default ./default-configs
```

4. Dump kurtosis-cdk configurations.

```bash
./zkevm_config.sh dump kurtosis-cdk ./kurtosis-cdk-configs
```

5. Compare configurations. You'll find diffs in `./diff`.

```bash
./zkevm_config.sh compare configs ./default-configs ./kurtosis-cdk-configs
```

6. Compare two specific files.

```bash
./zkevm_config.sh compare files ./default-configs/cdk-data-availability-config.toml ./kurtosis-cdk-configs/cdk-data-availability-config.toml
```
