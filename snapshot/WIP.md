On the snapshot feature, let's add more services: an L2. I want you to deep dive into the repo to understand how the L2s are spawned up inside kurtosis. In particular, the difference between op-geth and cdk-erigon based networks. In this iteration we are going to focus on op-geth in pesimistic consensus mode, but make the code flexible enough to accomodate op-geth in fep mode and cdk-erigon stacks in the future. Once you've gained understandment of how this works on kurtosis:

1. Find the op-geth and op-node within the given enclave
2. Extract the necessary config files and artifacts (all the stuff needed to run each component, such as the config file, private keys, ...)
3. Add the op-geth and op-node service definitions on the snapshot docker compose. Note that in the future there may be multiple instance of those services, so use the prefix (same prefix used on kurtosis, such as `001`)
4. Save all the needed files to run the agglayer under <snapshot dir>/config/<network prefix>
5. Do the necessary config tweaking: the config file extracted from the enclave will need adaptation in order to be used in the docker compose env. In particular the geth RPC will be different

Note: unlike the L1 images were the state is backed in, op-node and op-geth shouldn't have any state backed in + the only volumes to be sued should be the ones related to the config files and artifacts

---

polycli ulxly bridge asset --bridge-address 0xC8cbEBf950B9Df44d987c8619f092beA980fF038 --chain-id 2151908 --destination-address 0x1f7ad7caA53e35b4f0D138dC5CBF91aC108a2674 --destination-network 0 --private-key 0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625 --rpc-url http://localhost:11545 --value 1
polycli cdk ger monitor --ger-address 0x1f7ad7caA53e35b4f0D138dC5CBF91aC108a2674 --rollup-manager-address 0x6c6c009cC348976dB4A908c92B24433d4F6edA43 --rpc-url http://localhost:8545

---

curl -s http://localhost:11545   -X POST   -H "Content-Type: application/json"   --data '{
    "jsonrpc":"2.0",
    "method":"eth_getBlockByNumber",
    "params":["latest", false],
    "id":1
  }'


---

---

TODO:


make sure docker compose is down after snapshot gen

---

add bridge service to aggkit

---


remove unnecessary stuff once the snapshot is complete

---

test op-geth fep mode

---

test cdk-erigon x ???

---

single snapshot gens multiple output dirs?

---

speed up docker compose up -d

---

optional: add bridge spammer

---
wip
on the snapshot feature, edit the scripts to include a summary.json as part of the output of each snapshot. This file should have for each network (L1 + every deployed L2):

- relevant smart contract addrs
- URLs of all the services (all the exposed ports). For each of those, include the URL as it should be used inside the docker env and outside docker
- an array of relevant accounts, each item should have address, private key, description. A relevant account is any account that has a permissioned role on any of the deployed smart contract, or simply has balance