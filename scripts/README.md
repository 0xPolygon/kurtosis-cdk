# Scripts

## anvil-template-check/
Hermetic regression check for the configuration templates the `sequencer_type: anvil`
and two-L2 setups depend on: the aggkit, agglayer, zkevm-bridge-service and
aggkit-proxy `config.toml` files and the bridge UI `haproxy.cfg`. Each template is
rendered with Go `text/template` (the engine behind Kurtosis's `plan.render_templates`,
here with missing keys as errors) against a checked-in JSON fixture, then the script
asserts that every address and URL key the anvil branches own is present and
non-empty, that no template action or `<no value>` survives, that the agglayer
settlement sections match the agglayer version, that the two-L2 ranges render one
entry per network, and that the rendered `haproxy.cfg` passes `haproxy -c`. This
catches the silent-fallback failure class, where a missing `sequencer_type` branch
renders an empty string or drops the key. No Kurtosis enclave is required.

### Usage
```bash
./scripts/anvil-template-check/check.sh
```
Requires `go`, `jq` and Docker (set `ANVIL_TEMPLATE_CHECK_SKIP_HAPROXY=1` to skip the
`haproxy -c` check on a host without Docker).

## upgrade_forkid.sh
The main purpose of this script is to test Erigon behavior when upgrading forkid, and it can be taken as example/guide of required steps to upgrade an existing network.
The script itself takes care of deploying the Kurtosis CDK stack, halt sequencer and check it's in a right status, upgrading contracts, starting sequencer again, check it process the new forkid, and then removing the whole stack.
You can not use it as is to upgrade your existing stack, but you can easily adapt it for your context.

### Usage
From the root of repo, run:
```bash
./scripts/upgrade_forkid.sh 11 13
```

This would deploy a forkid 11 stack and then upgrade it to forkid 13.

These are the tested/supported combinations so far:
- Upgrading from forkid 12 to 13
- Upgrading from forkid 11 to 12
- Upgrading from forkid 11 to 13
- Upgrading from forkid 9 to 11
- Upgrading from forkid 9 to 12
- Upgrading from forkid 9 to 13
