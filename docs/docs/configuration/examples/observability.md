---
sidebar_position: 3
---

# Observability

## Introduction

This configuration is ideal for development teams requiring a complete testing environment with comprehensive monitoring. It deploys the default [CDK OP Geth](./cdk-opgeth.md) setup enhanced with debugging and observability tools, making it perfect for development, testing, and troubleshooting.

### What's Deployed?

- L1 Ethereum blockchain ([lighthouse/geth](https://github.com/ethpandaops/ethereum-package))
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer), and [mock prover](https://github.com/agglayer/provers))
- L2 Optimism blockchain ([op-geth](https://github.com/ethereum-optimism/op-geth) / [op-node](https://github.com/ethereum-optimism/optimism/tree/develop/op-node)) enhanced with [AggKit](https://github.com/agglayer/aggkit) for seamless Agglayer connectivity
- zkEVM bridge ([zkevm-bridge-service](https://github.com/0xPolygonHermez/zkevm-bridge-service)) to facilitate asset bridging between L1 and L2
- Additional services:
  - Blockchain explorer: [Blockscout](https://www.blockscout.com/)
  - Observability stack: [Prometheus](https://prometheus.io/) (metrics), [Grafana](https://grafana.com/) (dashboards), and [Panoptichain](https://github.com/0xPolygon/panoptichain) (blockchain monitoring)
  - Status checker: [status-checker](https://github.com/0xPolygon/status-checker) service to monitor environment health

### Use Cases

- Teams needing comprehensive monitoring and debugging tools
- Testing and troubleshooting rollup environments
- Development environments requiring full visibility into blockchain activity

### Deployment

```yaml title="params.yml"
args:
  additional_services:
    - blockscout
    - status_checker
    - observability
```

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file params.yml .
```

After deployment, retrieve service URLs with:

```bash
kurtosis port print cdk prometheus-001 http
kurtosis port print cdk grafana-001 http
```

Open the printed URLs in your browser to access metrics and dashboards.

## Metrics

Adding a service that emits Prometheus metrics to `kurtosis-cdk` is straightforward: ensure the service has a `prometheus` port configured.

```python
plan.add_service(
    name="service-a",
    config=ServiceConfig(
        ports={"prometheus": PortSpec(9090, application_protocol="http")},
    ),
)
```

To verify Prometheus is ingesting metrics correctly:

1. Run:

   ```bash
   curl $(kurtosis port print cdk panoptichain-001 prometheus)/metrics
   ```

   Adjust the `metrics` path if necessary for the service’s Prometheus configuration.

2. Navigate to:

   ```bash
   $(kurtosis port print cdk prometheus-001 http)/targets
   ```

   Confirm the service appears and query a service-specific metric.

## Dashboards

Several predefined dashboards are available, some with filters for `network`, `provider`, or `job`.

![dashboards](/img/dashboards.png)

The _Panoptichain_ dashboard displays metrics from [panoptichain](https://github.com/0xPolygon/panoptichain), an open-source blockchain monitoring tool that captures data via RPC calls.

![panoptichain](/img/panoptichain.png)

The _Services_ dashboard shows metrics for all services in `kurtosis-cdk`. When adding a new service with Prometheus metrics, add a row here or create a dedicated dashboard.

![services](/img/services.png)

### Saving Dashboards

By default, Grafana dashboard changes do not persist across kurtosis runs. To save a dashboard:

1. **Share → Export → Save to file.** Ensure _Export for sharing externally_ is **unchecked**.
2. Save the file to:
   [`static_files/additional_services/grafana-config/dashboards`](https://github.com/0xPolygon/kurtosis-cdk/tree/main/static_files/additional_services/grafana-config/dashboards)
3. Restart Grafana or `kurtosis-cdk`.

## Status Checks

Status checks are scripts that assess network health. They reside in [`static_files/additional_services/status-checker-config/checks`](https://github.com/0xPolygon/kurtosis-cdk/tree/main/static_files/additional_services/status-checker-config/checks).

### Writing Checks

Add a shebang-compatible script to the directory. Success or failure is determined by the script’s exit code. Use existing checks as examples and minimize false positives.

```bash title="block-number.sh"
#!/usr/bin/env bash
cast block-number --rpc-url $L1_RPC_URL
```

The container running status checks provides environment variables:

```python
env_vars = {
    "L1_RPC_URL": args.get("l1_rpc_url"),
    "L2_RPC_URL": l2_rpc_url,
    "SEQUENCER_RPC_URL": sequencer_rpc_url,
    "CONSENSUS_CONTRACT_TYPE": args.get("consensus_contract_type"),
}
```

### Viewing Results

To view status check results, run:

```bash
kurtosis service logs cdk status-checker-001 -f
```

Logs show each check’s result:

```json
[status-checker-001] {"level":"info","check":"l2-coinbase.sh","success":true,"time":"2025-06-17T19:24:20Z"}
```

The status checker also appears in the Grafana _Services_ dashboard:

![status-checker](/img/status-checker.png)
