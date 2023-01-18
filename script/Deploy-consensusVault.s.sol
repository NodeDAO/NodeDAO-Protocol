// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/rewards/ConsensusVault.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";

contract DeployConsensusVaultScript is Script {
    ConsensusVault  consensusVault;
    address payable consensusVaultProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        consensusVault = new ConsensusVault();

        consensusVaultProxy = payable(deployer.deploy(address(consensusVault)));

        ConsensusVault(consensusVaultProxy).initialize();

        vm.stopBroadcast();
    }
}
