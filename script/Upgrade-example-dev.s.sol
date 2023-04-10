// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVault.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/LiquidStaking.sol";
import "./utils/DeployProxy.sol";
import "forge-std/Script.sol";

contract DeployImplementScript is Script {
    LiquidStaking liquidStaking;

    NETH neth;
    ELVault vaultContract;

    ELVaultFactory vaultFactoryContract;

    VNFT vnft;

    NodeOperatorRegistry operatorRegistry;

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

        // deploy LiquidStaking implement
        liquidStaking = new LiquidStaking();

        vm.stopBroadcast();
    }
}

// forge script script/Upgrade-example-dev.s.sol:UpgradeLiquidStakingScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify --with-gas-price 30000000000 --retries 10 --delay 30
contract UpgradeLiquidStakingScript is Script {
    address payable liquidStakingProxy = payable(0xa8256fD3A31648D49D0f3551e6e45Db6f5f91d53);
    address payable beaconOracleProxy = payable(0x13766719dacc651065D5FF2a94831B46f84481b7);

    LiquidStaking liquidStaking;

    address[] memberArray = [
        0xe583DC38863aB4b5A94da77A6628e2119eaD4B18,
        0x3357c09eCf74C281B6f9CCfAf4D894979349AC4B,
        0x143848A303d424FD75995e5827358ba6d30a1801,
        0x2D9FdD22936e5577d368a3689c0387bac68EDf24
    ];

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
