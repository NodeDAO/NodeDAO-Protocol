// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "src/neth/NethLocking.sol";
import "./utils/DeployProxy.sol";

// forge script script/Deploy-nethLocking.s.sol:DeployScript --rpc-url $SCROLL_RPC_URL --broadcast --verify  --retries 10 --delay 30
contract DeployScript is Script {
    NethLocking nethLocking;
    address nethLockingProxy;
    address _dao = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        nethLocking = new NethLocking();

        nethLockingProxy = deployer.deploy(address(nethLocking));
        NethLocking(nethLockingProxy).initialize(_dao);

        console.log("===============nethLocking=================", address(nethLocking));
        console.log("===============nethLockingProxy=================", address(nethLockingProxy));

        vm.stopBroadcast();
    }
}