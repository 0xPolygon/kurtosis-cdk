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

   Adjust the `metrics` path if necessary for the service's Prometheus configuration.

2. Navigate to:

   ```bash
   $(kurtosis port print cdk prometheus-001 http)/targets
   ```

   Confirm the service appears and query a service-specific metric.

## Dashboards

Several predefined dashboards are available, some with filters for `network`, `provider`, or `job`.

![dashboards](/img/dashboards.png)

The _Panoptichain_ dashboard displays metrics from [Panoptichain](https://github.com/0xPolygon/panoptichain), an open-source blockchain monitoring tool that captures data via RPC calls. All Panoptichain metrics are prefixed with `panoptichain_`. View all available Panoptichain metrics [here](https://github.com/0xPolygon/panoptichain/blob/main/metrics.md).

![panoptichain](/img/panoptichain.png)

The _Services_ dashboard shows metrics for all services in `kurtosis-cdk`. When adding a new service with Prometheus metrics, add a row here or create a dedicated dashboard.

![services](/img/services.png)

### Saving Dashboards

By default, Grafana dashboard changes do not persist across kurtosis runs. To save a dashboard:

1. **Share → Export → Save to file.** Ensure _Export for sharing externally_ is **unchecked**.
2. Save the file to:
   [`static_files/additional_services/grafana/dashboards`](https://github.com/0xPolygon/kurtosis-cdk/tree/main/static_files/additional_services/grafana/dashboards)
3. Restart Grafana or `kurtosis-cdk`.

## Status Checks

Status checks are scripts that assess network health. They reside in [`static_files/additional_services/status-checker/checks`](https://github.com/0xPolygon/kurtosis-cdk/tree/main/static_files/additional_services/status-checker/checks).

### Writing Checks

Place each status-check script in the `checks` directory with a proper shebang (e.g. `#!/usr/bin/env bash`) on the first line so it can be executed directly. A script passes when it exits with code `0` and is considered failed on any non-zero exit code. Reference existing checks to maintain consistency and minimize false positives. Because status-check scripts are stateless and ephemeral between executions, required state must be managed externally. File-based storage or environment variables are suitable for simple state management, while a database should be used for more complex scenarios.

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
kurtosis service logs cdk status-checker-001 --follow
```

Logs show each check's result:

```json
[status-checker-001] {"level":"info","check":"l2-coinbase.sh","success":true,"time":"2025-06-17T19:24:20Z"}
```

The status checker also appears in the Grafana _Services_ dashboard:

![status-checker](/img/status-checker.png)

## Alerting

Alerting monitors Prometheus-ingested metrics and triggering notifications when defined thresholds are breached. A set of preconfigured alerting rules is included out of the box. It is recommended to use alerting for simple use cases where there are existing Prometheus metrics and the status-checker for more complex scenarios.

![alerting](/img/alerting.png)

### Slack Notifications

By default, Slack notifications are disabled. To enable them, set the following environment variables in [`grafana.star`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/src/additional_services/grafana.star#L10-L12):

- `SLACK_WEBHOOK_URL`
- `SLACK_CHANNEL`
- `SLACK_USERNAME`

When enabled, Grafana will post alert messages to the specified Slack channel during a Kurtosis run.

### Exporting Rules

To export and persist alerting rules:

1. In Grafana, go to **Alerting → Alert Rules**.
2. Click **Export → YAML → Download**.
3. Save the downloaded file as [`static_files/additional_services/grafana/alerting.yml.tmpl`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/static_files/additional_services/grafana/alerting.yml.tmpl).

![alerting-export](/img/alerting-export.png)
