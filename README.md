# NodeDAO Protocol

Made by:

![kinghash](./docs/images/kingHashLogo.PNG)

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

You can find more generic information about NodeDAO Protocol over [here](https://www.kinghash.com/).

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

To be updated.

## Ethereum

To be updated.

# Audits

To be updated.
