// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "forge-std/Script.sol";
import "src/rewards/ELVault.sol";

contract UpgradeableBeaconScript is Script {
    address payable upgradeableBeacon = payable(0xf88244e35f1dCb7Eb63f410f6FD1F0CB20aC97de);
    ELVault vault;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        vault = new ELVault();

        UpgradeableBeacon(upgradeableBeacon).upgradeTo(address(vault));

        vm.stopBroadcast();
    }
}
