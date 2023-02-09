// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/vault/ConsensusVault.sol";
import "forge-std/Script.sol";

contract UpgradeConsensusVaultScript is Script {
    address payable consensusVaultProxy = payable(0xf9db52Bb108F1D48427EBAf6468Ae2Ae22F6A5ed);
    ConsensusVault consensusVault;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        consensusVault = new ConsensusVault();

        ConsensusVault(consensusVaultProxy).upgradeTo(address(consensusVault));

        vm.stopBroadcast();
    }
}
