# Fault Injection and Chaos Tests using Kurtosis CDK

## Introduction

We can combine the [agglayer/e2e](https://github.com/agglayer/e2e) repository with Kurtosis CDK repository to conduct more advanced testing. The agglayer/e2e scenario allows network chaos testing for Docker containers using [Pumba](https://github.com/alexei-led/pumba) to simulate various network conditions and failures.

### What's Deployed?

- Default Kurtosis CDK stack

### Use Cases

- Teams looking to test Kurtosis CDK infrastructure under various scenarios

### Prerequisites

Along with the existing Kurtosis CDK prerequisites, we will also need the dependencies to run the chaos tests:

1. **Docker**: Running Docker containers to test against
2. **Pumba**: Network chaos engineering tool
3. **jq**: JSON processor for parsing test matrix
4. **PICT**: For generating test combinations

### Deployment

Deploy the default Kurtosis CDK setup without any arguments. This will spin up a CDK-OP-Geth stack deployment.

```bash
kurtosis run --enclave=cdk .
```

### Fault injection

Refer to the agglayer/e2e repository's detailed [chaos testing docs](https://github.com/agglayer/e2e/tree/main/scenarios/chaos-test) for more detail.
This guide will show a high level overview of how to quickly run the tests and what to expect from the output.

The chaos testing framework `pumba` allows you to inject network faults into running Docker containers to test system resilience and fault tolerance. It supports multiple types of network chaos including:

- Packet Loss: Simulates network unreliability
- Delay/Latency: Adds network latency and jitter
- Rate Limiting: Restricts network bandwidth
- Packet Duplication: Simulates network packet duplication
- Packet Corruption: Corrupts network packets
- Connection Drops: Uses iptables to drop specific connections

### Complete Workflow

1. **Generate test matrix**:
   ```bash
   cd assets/
   ./generate-matrix.bash
   ```

   For additional details on test matrix generation, refer to the [docs](https://github.com/agglayer/e2e/tree/main/scenarios/chaos-test#test-matrix-generation)

2. **Run chaos tests**:
   ```bash
   # Usage: ./network-chaos.bash <timeout> <path_to_test_matrix>
   # Run from the /chaos-test directory
   ./network-chaos.bash 60s assets/test_matrix.json
   ```

3. **Review results** in the generated `chaos_logs_*` directory:

    For additional details on interpreting the results, refer to the [docs](https://github.com/agglayer/e2e/tree/main/scenarios/chaos-test#log-analysis)