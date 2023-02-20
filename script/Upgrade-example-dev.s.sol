// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/BeaconOracle.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVault.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/LiquidStaking.sol";
import "forge-std/Script.sol";

contract DeployImplementScript is Script {
    LiquidStaking liquidStaking;

    NETH neth;
    ELVault vaultContract;

    ELVaultFactory vaultFactoryContract;

    VNFT vnft;

    NodeOperatorRegistry operatorRegistry;

    BeaconOracle beaconOracle;

    ConsensusVault consensusVault;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy ConsensusVault implement
        consensusVault = new ConsensusVault();

        // deploy nETH, no proxy
        neth = new NETH();

        // deploy vNFT implement
        vnft = new VNFT();

        // deploy ELVault implement
        vaultContract = new ELVault();

        // deploy ELVaultFactory implement
        vaultFactoryContract = new ELVaultFactory();

        // deploy NodeOperatorRegistry implement
        operatorRegistry = new NodeOperatorRegistry();

        // deploy BeaconOracle implement
        beaconOracle = new BeaconOracle();

        // deploy LiquidStaking implement
        liquidStaking = new LiquidStaking();

        vm.stopBroadcast();
    }
}

contract UpgradeLiquidStakingScript is Script {
    address payable liquidStakingProxy = payable(0x09F6E4018b091786890068F0e03DaaF344EA4768);

    LiquidStaking liquidStaking;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy LiquidStaking implement
        liquidStaking = new LiquidStaking();

        LiquidStaking(liquidStakingProxy).upgradeTo(address(liquidStaking));

        vm.stopBroadcast();
    }
}
