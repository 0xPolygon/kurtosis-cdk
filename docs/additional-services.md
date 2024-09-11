# Additional Services

A variety of additional services can be deployed alongside the CDK stack, each designed to enhance its functionality and capabilities.

Below is a list of services available for deployment using Kurtosis:

| Service | Description |
|-------- | ----------- |
| `arpeggio` | Deploys [Arpeggio](https://github.com/0xPolygon/arpeggio), a load balancing reverse-proxy for Ethereum RPC nodes (currently WIP) | 
| `blockscout` | Deploys the [Blockscout](https://www.blockscout.com/) stack, a comprehensive blockchain explorer for Ethereum-based networks, allowing exploration of transaction histories, account balances, and smart contract details. |
| `blutgang` | Deploys [Blutgang](https://github.com/rainshowerLabs/blutgang), an Ethereum load balancer that distributes network traffic evenly across multiple nodes to ensure high availability. |
| `pless_zkevm_node` | Deploys a permissionless [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node). |
| `prometheus_grafana` | Deploys [Prometheus](https://github.com/prometheus/prometheus) and [Grafana](https://github.com/grafana/grafana), two powerful monitoring tools that collect and visualize metrics for blockchain infrastructure health and performance. Additionally, it deploys [Panoptichain](https://github.com/0xPolygon/panoptichain), enhancing monitoring capabilities by allowing users to observe on-chain data and generate detailed Polygon CDK blockchain metrics. |
| `tx_spammer` | Deploys a transaction spammer. |

Here is a simple example that deploys Blockscout, Prometheus, Grafana, and Panoptichain:

```yml
args:
  additional_services:
    - blockscout
    - prometheus_grafana
```

Once the services are deployed, you can access their web interfaces and interact with their RPCs using the following commands:

Access the different web interfaces:

- Arpeggio (WIP):

```bash
open $(kurtosis port print cdk-v1 arpeggio-001 rpc)
open $(kurtosis port print cdk-v1 arpeggio-001 ws)
```

- Blockscout:

```bash
open $(kurtosis port print cdk-v1 bs-frontend-001 frontend)
```

- Prometheus:

```bash
open $(kurtosis port print cdk-v1 prometheus-001 http)
```

- Grafana:

```bash
open $(kurtosis port print cdk-v1 grafana-001 dashboards)
```

Utilize the different RPC endpoints:

- Interact with Blutgang's load balancer:

```bash
cast bn --rpc-url $(kurtosis port print cdk-v1 blutgang-001 http)
```

- Connect to the permissionless zkevm-node:

```bash
cast bn --rpc-url $(kurtosis port print cdk-v1 zkevm-node-rpc-pless-001 http-rpc)
```
