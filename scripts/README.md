# Scripts

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
