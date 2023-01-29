// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/LiquidStaking.sol";
import "forge-std/Script.sol";

contract UpgradeConsensusVaultScript is Script {
    address payable liquidStakingProxy = payable(0x09F6E4018b091786890068F0e03DaaF344EA4768);
    LiquidStaking liquidStaking;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        liquidStaking = new LiquidStaking();

        LiquidStaking(liquidStakingProxy).upgradeTo(address(liquidStaking));

        vm.stopBroadcast();
    }
}
