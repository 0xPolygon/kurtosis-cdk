---
sidebar_position: 3
---

# Observability

This configuration is ideal for development teams who need a complete testing environment with comprehensive monitoring. It deploys the default [CDK OP Geth](./cdk-opgeth.md) setup enhanced with debugging and observability tools, making it perfect for development, testing, and troubleshooting.

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- L2 Optimism blockchain (op-geth/op-node) enhanced with [AggKit](https://github.com/agglayer/aggkit) for seamless Agglayer connectivity.
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.
- Additional services:
  - Blockchain explorer: [Blockscout](https://www.blockscout.com/).
  - Observability stack: [Prometheus](https://prometheus.io/) (metrics), [Grafana](https://grafana.com/) (dashboards) and [Panoptichain](https://github.com/0xPolygon/panoptichain) (blockchain monitoring).
  - Status checker service to monitor environment health.

#### Best For

- Teams requiring comprehensive monitoring and debugging tools.
- Testing and troubleshooting rollup environments.
- Development environments needing full visibility into blockchain activity.

#### Deployment

```yml title="params.yml"
args:
  additional_services:
    - blockscout
    - observability
    - status_checker
```

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file params.yml .
```

After deploying, retrieve the service URLs with:

```bash
kurtosis port print cdk prometheus-001 http
kurtosis port print cdk grafana-001 http
```

Open the printed URLs in your browser to access the metrics and dashboards.
