# Additional Services

Kurtosis allows you to deploy a variety of additional services alongside the CDK stack. Each service is designed to enhance the functionality and capabilities of the devnet. Below is a list of available services that can be deployed using Kurtosis:

- `blockscout`: Deploys the [Blockscout](https://www.blockscout.com/) stack, a comprehensive blockchain explorer for Ethereum-based networks. Blockscout provides an interface for users to explore transaction histories, account balances, and smart contract details.
- `blutgang`: Deploys [Blutgang](https://github.com/rainshowerLabs/blutgang), an Ethereum load balancer. Blutgang is useful for distributing network traffic evenly across multiple nodes, ensuring high availability and
- `panoptichain`: Deploys [Panoptichain](https://github.com/0xPolygon/panoptichain), a blockchain monitoring tool designed for observing on-chain data and creating Prometheus metrics.
- `pless_zkevm_node`: Deploys a permissionless [zkevm-node](https://github.com/0xPolygonHermez/zkevm-node).
- `prometheus_grafana`: Deploys [Prometheus](https://github.com/prometheus/prometheus) and [Grafana](https://github.com/grafana/grafana), two powerful monitoring tools. Prometheus is used for collecting and querying metrics, while Grafana provides a rich visualization layer. Together, they offer a robust solution for monitoring the health and performance of your blockchain infrastructure.

Here is a simple example that deploys Blockscout, Prometheus, Grafana and Panoptichain.

```yml
args:
  additional_services:
    - blockscout
    - prometheus_grafana
    - panoptichain
```
