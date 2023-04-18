// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/WithdrawOracle.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVault.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/NodeDaoTreasury.sol";

// Goerli settings
abstract contract GoerliHelperContractV2 {
    address deployerAddress = 0x7A7df7396A82A5F4eEb7e023C4874c00e8616157;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoMultisigContract = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

    address timelock = 0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb ;
}

// Mainnet settings
abstract contract MainnetHelperContractV2 {
    // https://etherscan.io/address/0x178b7401c32a4aab5ef128458888779eaaf4e78a
    address deployerAddress = 0x178B7401C32A4aab5EF128458888779eaAF4E78a;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;

    address timelock = 0x16F692525f3b8c8a96F8c945D365Da958Fb5735B;
}

contract GoerliDeployNodeDaoTreasury is Script, GoerliHelperContractV2 {
    NodeDaoTreasury nodeDaoTreasury;
    address payable nodeDaoTreasuryProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury();
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        nodeDaoTreasuryProxy = payable(deployer.deploy(address(nodeDaoTreasury)));
        console.log("===============nodeDaoTreasuryProxy=================", address(nodeDaoTreasuryProxy));

        NodeDaoTreasury(nodeDaoTreasuryProxy).initialize(_daoMultisigContract);
        NodeDaoTreasury(nodeDaoTreasuryProxy).transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
}

contract MainnetDeployNodeDaoTreasury is Script, MainnetHelperContractV2 {
    NodeDaoTreasury nodeDaoTreasury;
    address payable nodeDaoTreasuryProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury();
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        nodeDaoTreasuryProxy = payable(deployer.deploy(address(nodeDaoTreasury)));
        console.log("===============nodeDaoTreasuryProxy=================", address(nodeDaoTreasuryProxy));

        NodeDaoTreasury(nodeDaoTreasuryProxy).initialize(_daoMultisigContract);
        NodeDaoTreasury(nodeDaoTreasuryProxy).transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
}
