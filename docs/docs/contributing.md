---
sidebar_position: 5
---

# Contributing

Thank you for your interest in contributing to the package!

This guide will help you get started quickly. For more details, see the [full documentation](./introduction/overview.md).

## How to Contribute

- Fork and clone the repository.
- Create a feature or fix branch.
- Make your changes and add tests if needed.
- Run linter, tests, and build docs if changed.
- Open a pull request with a clear description.
- Ensure CI passes before requesting review.

### Linting

Run Kurtosis linter:

```bash
kurtosis lint --format .
```

### Testing

#### Unit Tests

We rely on [kurtosis-test](https://github.com/ethereum-optimism/kurtosis-test) to run a set of unit tests against the Starlark code.

```bash
git clone https://github.com/ethereum-optimism/kurtosis-test.git
pushd kurtosis-test
git checkout v0.0.6
go build -o kurtosis-test cli/main.go
cp kurtosis-test /usr/local/bin
```

Then run the Kurtosis tests.

```bash
# in kurtosis-cdk
kurtosis-test .
```

#### E2E Tests

:::info
You will need to have the test runner deployed in your environment to run e2e tests with this command.
:::

Run bridge tests:

```bash
kurtosis service exec pos test-runner "bats --filter 'bridge native ETH from L2 to L1' tests/agglayer/bridges.bats"
```

### Documentation

To build the docs:

```bash
cd docs
npm run build
```

To preview docs locally:

```bash
npm run serve
```

Then visit http://localhost:3000.

## Need Help?

- Check the [full documentation](./introduction/overview.md).
- Open an [issue](https://github.com/0xPolygon/kurtosis-polygon-pos/issues/new).
