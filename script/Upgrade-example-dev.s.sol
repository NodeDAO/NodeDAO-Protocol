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
import "./utils/DeployProxy.sol";
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

contract DeployExampleScript is Script, DeployProxy {
    address payable liquidStakingProxy = payable(0xa8256fD3A31648D49D0f3551e6e45Db6f5f91d53);
    address vnftProxy = 0xe3CE494D51Cb9806187b5Deca1B4B06c97e52EFc;
    address dao = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 _genesisTime = 1616508000;

    BeaconOracle beaconOracle;
    address beaconOracleProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy BeaconOracle implement
        beaconOracle = new BeaconOracle();

        // deploy BeaconOracle proxy
        setType("uups");
        beaconOracleProxy = deploy(address(beaconOracle), abi.encodeWithSelector(BeaconOracle.initialize.selector, dao, _genesisTime, vnftProxy));

        // BeaconOracle setLiquidStaking
        BeaconOracle(beaconOracleProxy).setLiquidStaking(address(liquidStakingProxy));

        console.log("========beaconOracleProxy: ", beaconOracleProxy);

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
        // liquidStaking = new LiquidStaking();
        // LiquidStaking(liquidStakingProxy).upgradeTo(address(liquidStaking));

        // LiquidStaking(liquidStakingProxy).setBeaconOracleContract(address(0x13766719dacc651065D5FF2a94831B46f84481b7));

        // BeaconOracle(beaconOracleProxy).resetEpochsPerFrame(25);

        // BeaconOracle addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            BeaconOracle(beaconOracleProxy).addOracleMember(memberArray[i]);
        }

        vm.stopBroadcast();
    }
}
