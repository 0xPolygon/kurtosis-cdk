# Keys Usage

This doc tracks keys being used in Kurtosis CDK. It aims to document:
- The associated role/component
  - e.g. Agglayer, Aggkit, CDK-OP-Geth, etc...
- The purpose of the key
  - e.g. signing certificates, auto-claiming bridge transactions, etc...
- Its current permissions
  - e.g. admin role of a specific smart contract

And aims to assign minimal privileges to make sure keys are not overused and only cover specific functions.

## Individual Keys

| Key Name | Arg Name | Address | Private Key | Component | Purpose | Permissions |
|----------|---------|---------|-------------|-----------|---------|-------------|
| **Sequencer** | l2_sequencer_address | `0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed` | `0x183c492d0ba156041a7f31a1b188958a7a22eebadbc6d5c4895da5ece80e1a98` | CDK Sequencer | Transaction sequencing and block production | Sequencer role in rollup contracts, transaction ordering |
| **Aggregator** | l2_aggregator_address | `0x85dd37b4DbBdEB0Ff2ad6e717C2BbA18a2eD4B03` | `0x2cb77c2cca48d3fee64c14d73564fd6e90676a4f6da6545681e10c8b9b22fce2` | CDK Aggregator | Proof aggregation and batch submission to L1 | Aggregator role in rollup contracts |
| **Admin** | l2_admin_address | `0xE34aaF64b29273B7D567FCFc40544c014EEe9970` | `0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625` | Contract Administration | Initial contract deployment and admin operations | DEFAULT_ADMIN_ROLE (initial), bridge admin, rollup admin, optimisticModeManager, aggchainManager, additional services such as tx spammer, bridge spammer and test runner generate new keys derived from this Admin key |
| **Data Availability Committee (DAC)** | l2_dac_address | `0x5951F5b2604c9B42E478d5e2B2437F44073eF9A6` | `0x85d836ee6ea6f48bae27b31535e6fc2eefe056f2276b9353aafb294277d8159b` | CDK Validium | Data availability committee member for validium mode | DAC member role, data availability attestation |
| **Aggoracle** | l2_aggoracle_address | `0x0b68058E5b2592b1f472AdFe106305295A332A7C` | `0x6d1d3ef5765cf34176d42276edd7a479ed5dc8dbf35182dfdb12e8aafe0a4919` | Aggkit Oracle | Oracle operations for cross-chain data | Oracle data submission and validation, global exit root updater |
| **Sovereign Admin** | l2_sovereignadmin_address | `0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16` | `0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0` | Sovereign Rollup Administration | Sovereign rollup management and bridge operations | Bridge manager role |
| **Claim Sponsor** | l2_claimsponsor_address | `0x635243A11B41072264Df6c9186e3f473402F94e9` | `0x986b325f6f855236b0b04582a19fe0301eeecb343d0f660c61805299dbf250eb` | Bridge Infrastructure | Sponsoring bridge claim transactions in Aggkit/CDK-Node/LegacyBridge | Bridge transaction sponsoring in Aggkit |

## Committee and Multi-Member Keys

| Committee | Component | Purpose | Key Generation | Permissions |
|-----------|-----------|---------|----------------|-------------|
| **Aggoracle Committee Members** | Aggkit Oracle Committee | Distributed oracle operations with multiple signers | Derived from mnemonic using indices 0-N<br/>Mnemonic: `"lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop"` | Committee member roles for oracle consensus |
| **Aggsender Validator Committee** | Aggkit Validator Committee | Multi-validator consensus for aggsender operations | Derived from same mnemonic using indices 2-N (starts from index 2) | Validator committee member roles |
