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

| Key Name | Address | Private Key | Component | Purpose | Permissions |
|----------|---------|-------------|-----------|---------|-------------|
| **Sequencer** | `0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed` | `0x183c492d0ba156041a7f31a1b188958a7a22eebadbc6d5c4895da5ece80e1a98` | CDK Sequencer | Transaction sequencing and block production | Sequencer role in rollup contracts, transaction ordering |
| **Aggregator** | `0x85dd37b4DbBdEB0Ff2ad6e717C2BbA18a2eD4B03` | `0x2cb77c2cca48d3fee64c14d73564fd6e90676a4f6da6545681e10c8b9b22fce2` | CDK Aggregator | Proof aggregation and batch submission to L1 | Aggregator role in rollup contracts |
| **Claim Transaction Manager** | `0x5f5dB0D4D58310F53713eF4Df80ba6717868A9f8` | `0x8d5c9ecd4ba2a195db3777c8412f8e3370ae9adffac222a54a84e116c7f8b934` | CDK Bridge | Auto-claiming bridge transactions in the Bridge Service | Bridge transaction management in the Bridge Service |
| **Timelock** | `0x130aA39Aa80407BD251c3d274d161ca302c52B7A` | `0x80051baf5a0a749296b9dcdb4a38a264d2eea6d43edcf012d20b5560708cf45f` | Contract Administration | Time-delayed contract administration and governance | EXECUTOR_ROLE, DEFAULT_ADMIN_ROLE (after timelock setup) |
| **Admin** | `0xE34aaF64b29273B7D567FCFc40544c014EEe9970` | `0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625` | Contract Administration | Initial contract deployment and admin operations | DEFAULT_ADMIN_ROLE (initial), bridge admin, rollup admin, optimisticModeManager, aggchainManager, additional services such as tx spammer, bridge spammer and test runner generate new keys derived from this Admin key |
| **Agglayer** | `0x18481b38dd03208d179019E7352c9aC9cD6d540E` | `0x1d45f90c0a9814d8b8af968fa0677dab2a8ff0266f33b136e560fe420858a419` | Agglayer | Cross-chain operations and agglayer coordination | Agglayer validator/coordinator role |
| **Data Availability Committee (DAC)** | `0x5951F5b2604c9B42E478d5e2B2437F44073eF9A6` | `0x85d836ee6ea6f48bae27b31535e6fc2eefe056f2276b9353aafb294277d8159b` | CDK Validium | Data availability committee member for validium mode | DAC member role, data availability attestation |
| **Aggoracle** | `0x0b68058E5b2592b1f472AdFe106305295A332A7C` | `0x6d1d3ef5765cf34176d42276edd7a479ed5dc8dbf35182dfdb12e8aafe0a4919` | Aggkit Oracle | Oracle operations for cross-chain data | Oracle data submission and validation |
| **Sovereign Admin** | `0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16` | `0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0` | Sovereign Rollup Administration | Sovereign rollup management and bridge operations | Bridge manager role, global exit root updater |
| **Claim Sponsor** | `0x635243A11B41072264Df6c9186e3f473402F94e9` | `0x986b325f6f855236b0b04582a19fe0301eeecb343d0f660c61805299dbf250eb` | Bridge Infrastructure | Sponsoring bridge claim transactions in Aggkit | Bridge transaction sponsoring in Aggkit |
| **Aggsender Validator** | `0xE0005545D8b2a84c2380fAaa2201D92345Bd0F6F` | `0x33df0149c16a7dd8d73c88b15cb1d8c05e5cb5cfd4e2bcbbb1ced9c3a53c46b2` | Aggkit Validator | Validator operations in aggsender component | Validator role in aggsender |

## Committee and Multi-Member Keys

| Committee | Component | Purpose | Key Generation | Permissions |
|-----------|-----------|---------|----------------|-------------|
| **Aggoracle Committee Members** | Aggkit Oracle Committee | Distributed oracle operations with multiple signers | Derived from mnemonic using indices 0-N<br/>Mnemonic: `"lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop"` | Committee member roles for oracle consensus |
| **Aggsender Validator Committee** | Aggkit Validator Committee | Multi-validator consensus for aggsender operations | Derived from same mnemonic using indices 2-N (starts from index 2) | Validator committee member roles |
