*** Set Up a Permissionless Node

In addition to the core stack, you can also attach and synchronize a
permissionless node. Of course, you'll need the CDK stack running from
the previous commands. Assuming that has run and correctly created a
network, you'll need to pull the genesis file artifact out and add it
to your ~permissionless_node~ kurtosis package.

#+begin_src bash
rm -r /tmp/zkevm
kurtosis files download cdk-v1 genesis /tmp
cp /tmp/genesis.json templates/permissionless-node/genesis.json
#+end_src

Now that we have the right genesis file, we can add a permissionless
node to the ~cdk-v1~ enclave:

#+begin_src bash
kurtosis run --enclave cdk-v1 --args-file params.yml --main-file zkevm_permissionless_node.star .
#+end_src

**** Remote Permissionless Testing

You can use the permissionless package to sync data from a production
network as well. First you'll need to get the genesis file and it
should be populated already with the CDK fields like:
- ~rollupCreationBlockNumber~
- ~rollupManagerCreationBlockNumber~
- ~L1Config.chainId~
- ~L1Config.polygonZkEVMGlobalExitRootAddress~
- ~L1Config.polygonRollupManagerAddress~
- ~L1Config.polTokenAddress~
- ~L1Config.polygonZkEVMAddress~

If you're unsure how to populate these fields please check out how
it's done within [[./templates/run-contract-setup.sh][run-constract-setup.sh]]. When you have the genesis
file ready, drop it into [[./templates/permissionless-node/genesis.json]].

In addition to the genesis setup, we'll also need to tweak a parameter
in [[./params.yml]]:

- ~l1_rpc_url~ will most likely need to be changed to be your actual
  L1 network. Most likely Sepolia or mainnet

There are other parameters that might seem like they should be
changed, e.g. ~l1_chain_id~, but those aren't actually used for the
permisionless setup. The most important thing is just to update the
RPC URL.

Once you've done that, you should be good to go and you can start
synchronizing with ths command:

#+begin_src bash
kurtosis run --enclave cdk-v1 --args-file params.yml --main-file zkevm_permissionless_node.star .
#+end_src