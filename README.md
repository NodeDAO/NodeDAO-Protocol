# NodeDAO Protocol

Made by:

[![HashKing](./docs/images/HashKingLogo.svg)](https://www.hashking.fi)

![node](https://img.shields.io/badge/node-v10.15.3-green)
![npm](https://img.shields.io/badge/npm-v6.9.0-green)
![python](https://img.shields.io/badge/python-v3.8.10-green)
![solidity](https://img.shields.io/badge/solidity-0.8.7-brightgreen)
![license](https://img.shields.io/github/license/King-Hash-Org/NodeDAO-Protocol)
![contributors](https://img.shields.io/github/contributors/King-Hash-Org/NodeDAO-Protocol)

<!--
| Statements                  | Branches                | Functions                 | Lines             |
| --------------------------- | ----------------------- | ------------------------- | ----------------- |
| ![Statements](https://img.shields.io/badge/statements-32.09%25-red.svg?style=flat) | ![Branches](https://img.shields.io/badge/branches-30.30%25-red.svg?style=flat) | ![Functions](https://img.shields.io/badge/functions-19.68%25-red.svg?style=flat) | ![Lines](https://img.shields.io/badge/lines-36.36%25-red.svg?style=flat) |
-->

This repository contains the core smart contracts for the [NodeDAO Protocol](https://nodedao.com/). NodeDAO Protocol is a smart contract for the next generation of liquid staking derivatives. It encompasses all the concepts from traditional liquid staking, re-staking, Distributed Validators & Validator NFT in a single protocol.

**Overview**

* [Architecture](./docs/architecture.md)
* [NETH (Liquid Staking)](./docs/liquidStaking.md)
* [vNFT (Validator NFT)](./docs/validatorNFT.md)
* [NodeOpratorRegistry](./docs/nodeOperatorRegistry.md)
* [BeaconOracle](./docs/beaconOracle.md)
* [Vaults](./docs/vaults.md)

You can find more generic information about NodeDAO Protocol over [here](https://doc.nodedao.com/).

# Quick Commands

Try running some of the following tasks:

```shell
forge help
forge test --vvvv
forge test --gas-report
forge build
forge clean
forge coverage
forge remappings
```

# Setting Up

1. Ensure you have installed `node ^v10.15.3` and `npm ^6.9.0`. We recommend using `nvm` to install both `node` and `npm`. You can find the `nvm` installation instructions [here](https://github.com/nvm-sh/nvm#installing-and-updating).
2. Ensure you have installed [Foundry](https://book.getfoundry.sh/getting-started/installation).
3. Run `forge install` to install the dependencies.
4. Run `forge build` to compile the code.
5. Run `forge clean` when you run into issues.
6. Run `forge test` to run the tests.

# Deploy

Pre-requisite:

Setup your `.env` with the following keys:

```
GOERLI_RPC_URL=https://api.chainup.net/ethereum/goerli/<YOUR_CHAINUP_API_KEY>
PRIVATE_KEY=<YOUR_PRIVATE_KEY>
ETHERSCAN_API_KEY=<YOUR_ETHERSCAN_API_KEY>
```

# Other Tools

## Coverage

To get code coverage do `forge coverage`.

We want 100% coverage on any smart contract code that gets deployed. If code doesn't need to be used, it should not be there. And whatever code does exist in the smart contract needs to be run by the tests.

## Slither - Security Analyzer

`pip3 install slither-analyzer` and
`slither .` inside the repo.

We also recommend to install the [slither vscode extension](https://marketplace.visualstudio.com/items?itemName=trailofbits.slither-vscode).

Run it after major changes and ensure there arent any warnings / errors.

To disable slither, you can add `// slither-disable-next-line DETECTOR_NAME`.

You can find `DETECTOR_NAME` [here](https://github.com/crytic/slither/wiki/Detector-Documentation).

## Surya - GraphViz for Architecture

Install Surya using : `npm install -g surya`

To create a graphviz summary of all the function calls do, `surya graph contracts/**/*.sol > FM_full.dot` and open `FM_full.dot` using a graphviz plugin on VSCode.

`surya describe contracts/**/*.sol` will summarize the contracts and point out fn modifiers / payments. It's useful to get an overview.

You can see further instructons for Surya [here](https://github.com/ConsenSys/surya).


# Contracts 
## Goerli

TimelockController: 0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb

LiquidStaking Proxy: 0x949AC43bb71F8710B0F1193880b338f0323DeB1a

NodeOperatorRegistry Proxy: 0x20C43025E44984375c4dC882bFF2016C6E601f0A

ELVaultFactory Proxy: 0x56dF1C19d0993Ac4B372c66E4d0512de875792B1

VNFT Proxy: 0x3CB42bb75Cf1BcC077010ac1E3d3Be22D13326FA

NETH: 0x408F53a38db844B167B66f001fDc49613E25eC78

ConsensusVault Proxy: 0x138d5D3C2d7d68bFC653726c8a5E8bA301452202

LargeStakingProxy:   0x8C73a9F648c5A596bE37DC7A821FeFb3D67f57d3  

LargeStakingELRewardFactory Proxy： 0x7f92E2d2F808D77CCaf6D03FE90F36eB6b211A01

OperatorSlash Proxy:  0x69b11EF441EEb3A7cb2A3d82bC31F90596A7C48d

WithdrawalRequest Proxy:  0x006e69F509E31c91263C03a744B47c3b03eAC391

VaultManager Proxy:  0xb5bE48AE75b1085CBA8d4c16157050d4C9a80Aa0

WithdrawOracle Proxy: 0x1E726f6111B58e74CCD63d5b659191A49366CaD9

MultiHashConsensus Proxy: 0xBF7b3b741052D33ca0f522A0D70589e350d38bb7

LargeStakeOracle Proxy: 0xB8E0EE431d78273d7BAefEB0Fb64897626b0B8FA

## Ethereum

TimelockController: 0x16F692525f3b8c8a96F8c945D365Da958Fb5735B

LiquidStaking Proxy: 0x8103151E2377e78C04a3d2564e20542680ed3096

NodeOperatorRegistry Proxy: 0x8742178Ac172eC7235E54808d5F327C30A51c492

ELVaultFactory Proxy: 0x50A6EfeF391f775d7386CaFCA3Ec5Ce15f80b836

VNFT Proxy: 0x58553F5c5a6AEE89EaBFd42c231A18aB0872700d

NETH: 0xC6572019548dfeBA782bA5a2093C836626C7789A

ConsensusVault Proxy: 0x4b8Dc35b44296D8D6DCc7aFEBBbe283c997E80Ae

LargeStaking Proxy：0xBBd19e8F766Dcc94D50e47502b79C81cdaD484B8

LargeStakingELRewardFactory Proxy：0xA0b4f1a17786C80B8CfF0378a7f58De0D61b2eE3

NodeDaoTreasury: 0xd8d5b090A09F804eFc1e83a5B2f88af82346B066

OperatorSlash Proxy: 0x82c87cC83c9fA09DAdBEBFB8f8b9152Ee6104B5d

WithdrawalRequest Proxy: 0xE81fC969D14Cad8537ebAFa2a1c478F29d7840FC

VaultManager Proxy: 0x878bd0593Dfc1Ff302e3a20E98fC4F97CF516C15

WithdrawOracle Proxy: 0x503525159C0174C7758fe3D6C8eeCC595768a7A1

MultiHashConsensus Proxy： 0xe837C18e2f9863dA77fE575B67A0f406AD2CCac3

LargeStakeOracle Proxy：0xCc68D60fa4Ba7Def20E1Cba33D26C89847825A87

# Audits

You can see all audits report for NodeDAO here(https://github.com/NodeDAO/audits).

