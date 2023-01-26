// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/BeaconOracle.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/rewards/ELVault.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "src/rewards/ConsensusVault.sol";
import "src/rewards/ELVaultFactory.sol";

// deploy BeaconOracleScript
// 1. export
// export GOERLI_RPC_URL=""
// export PRIVATE_KEY=""
// export ETHERSCAN_API_KEY=""
// 2. execute cmd
// forge script script/Deploy-BeaconOracle.s.sol:DeployBeaconOracleScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify
contract DeployBeaconOracleScript is Script {
    address _dao = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

    BeaconOracle beaconOracle;
    address beaconOracleProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        beaconOracle = new BeaconOracle();

        beaconOracleProxy = deployer.deploy(address(beaconOracle));

        BeaconOracle(beaconOracleProxy).initialize(_dao);

        vm.stopBroadcast();
    }
}
