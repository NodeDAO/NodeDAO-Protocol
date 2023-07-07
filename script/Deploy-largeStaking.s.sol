// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "src/OperatorSlash.sol";
import "forge-std/console.sol";
import "src/largeStaking/ELReward.sol";
import "src/largeStaking/ELRewardFactory.sol";
import "src/largeStaking/LargeStaking.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/VaultManager.sol";

// Goerli settings
abstract contract GoerliHelperContractV2 {
    address deployerAddress = 0x7A7df7396A82A5F4eEb7e023C4874c00e8616157;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoMultisigContract = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoVaultContract = 0x4eAd195725669C2213287EC76baab2eBD13ff3b1;

    address _consensusOracleContract = 0x1E726f6111B58e74CCD63d5b659191A49366CaD9;

    // goerli: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b
    // mainnet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    address depositContract = 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b;

    address payable operatorRegistryProxy = payable(0x20C43025E44984375c4dC882bFF2016C6E601f0A);
    address payable operatorSlashProxy = payable(0x69b11EF441EEb3A7cb2A3d82bC31F90596A7C48d);
}

// Mainnet settings
abstract contract MainnetHelperContractV2 {
    // https://etherscan.io/address/0x178b7401c32a4aab5ef128458888779eaaf4e78a
    address deployerAddress = 0x178B7401C32A4aab5EF128458888779eaAF4E78a;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0xeF76D4e75154739F75F6068b3470c7968cC3Fcd1;
    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;
    address _daoVaultContract = 0x79285fd2224cBC0b25065C49537b72c1a4567AFC;

    // goerli: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b
    // mainnet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    address depositContract = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    address payable operatorRegistryProxy = payable(0x8742178Ac172eC7235E54808d5F327C30A51c492);
}

contract GoerliDeployLargeStakingScript is Script, GoerliHelperContractV2 {
    ELReward eLRewardContract;
    OperatorSlash operatorSlashContract;
    NodeOperatorRegistry nodeOperatorRegistryContract;
    VaultManager vaultManagerContract;

    ELRewardFactory eLRewardFactoryContract;
    address eLRewardFactoryContractProxy;

    LargeStaking largeStakingContract;
    address largeStakingContractProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy
        operatorSlashContract = new OperatorSlash();
        nodeOperatorRegistryContract = new NodeOperatorRegistry();
        eLRewardContract = new ELReward();
        vaultManagerContract = new VaultManager();

        eLRewardFactoryContract = new ELRewardFactory();
        eLRewardFactoryContractProxy = deployer.deploy(address(eLRewardFactoryContract));

        largeStakingContract = new LargeStaking();
        largeStakingContractProxy = deployer.deploy(address(largeStakingContract));

        // initialize
        ELRewardFactory(eLRewardFactoryContractProxy).initialize(address(eLRewardContract), _daoEOA);

        LargeStaking(largeStakingContractProxy).initialize(
            _daoEOA,
            _daoVaultContract,
            operatorRegistryProxy,
            operatorSlashProxy,
            _consensusOracleContract,
            eLRewardFactoryContractProxy,
            depositContract
        );

        console.log("=========operatorSlashContract===========", address(operatorSlashContract));
        console.log("=========vaultManagerContract===========", address(vaultManagerContract));
        console.log("=========nodeOperatorRegistryContract===========", address(nodeOperatorRegistryContract));
        console.log("=========eLRewardContract===========", address(eLRewardContract));
        console.log("=========eLRewardFactoryContract===========", address(eLRewardFactoryContract));
        console.log("=========eLRewardFactoryContractProxy===========", address(eLRewardFactoryContractProxy));
        console.log("=========largeStakingContract===========", address(largeStakingContract));
        console.log("=========largeStakingContractProxy===========", address(largeStakingContractProxy));

        vm.stopBroadcast();
    }
}

