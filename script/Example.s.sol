// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "src/oracles/BeaconOracle.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";

contract ExampleScript is Script {
    BeaconOracle implementation;

    address _dao = address(1);

    function setUp() public {
        implementation = new BeaconOracle();

    }

    function run() public {
        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        address admin = msg.sender;
        address proxyAddress = deployer.deploy(address(implementation), admin);
        BeaconOracle(proxyAddress).initialize(_dao);
        vm.broadcast();
    }
}
