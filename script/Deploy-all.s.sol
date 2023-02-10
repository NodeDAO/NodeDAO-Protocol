// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/BeaconOracle.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVault.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";

contract DeployAllScript is Script {
    address _dao = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoValutAddress = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address depositContract = 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b;

    LiquidStaking liquidStaking;
    address payable liquidStakingProxy;

    NETH neth;
    ELVault vaultContract;

    ELVaultFactory vaultFactoryContract;
    address vaultFactoryContractProxy;

    VNFT vnft;
    address vnftProxy;

    NodeOperatorRegistry operatorRegistry;
    address operatorRegistryProxy;

    BeaconOracle beaconOracle;
    address beaconOracleProxy;

    ConsensusVault consensusVault;
    address payable consensusVaultProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        // no proxy
        neth = new NETH();

        // ELVaultFactory
        vaultContract = new ELVault();
        vaultFactoryContract = new ELVaultFactory();

        vnft = new VNFT();
        operatorRegistry = new NodeOperatorRegistry();
        beaconOracle = new BeaconOracle();
        liquidStaking = new LiquidStaking();

        vnftProxy = deployer.deploy(address(vnft));
        operatorRegistryProxy = deployer.deploy(address(operatorRegistry));

        beaconOracleProxy = deployer.deploy(address(beaconOracle));
        liquidStakingProxy = payable(deployer.deploy(address(liquidStaking)));

        // ConsensusVault
        consensusVault = new ConsensusVault();
        consensusVaultProxy = payable(deployer.deploy(address(consensusVault)));
        ConsensusVault(consensusVaultProxy).initialize(_dao, address(liquidStakingProxy));

        vaultFactoryContractProxy = deployer.deploy(address(vaultFactoryContract));
        ELVaultFactory(vaultFactoryContractProxy).initialize(
            address(vaultContract), address(vnftProxy), address(liquidStakingProxy), _dao
        );
        ELVaultFactory(vaultFactoryContractProxy).setNodeOperatorRegistry(address(operatorRegistryProxy));

        // initialize
        VNFT(vnftProxy).initialize();
        NodeOperatorRegistry(operatorRegistryProxy).initialize(
            _dao, _daoValutAddress, address(vaultFactoryContractProxy), address(vnftProxy)
        );

        // goerli: 1616508000
        // mainnet: 1606824023
        uint64 genesisTime = 1616508000;
        BeaconOracle(beaconOracleProxy).initialize(_dao, genesisTime);
        LiquidStaking(liquidStakingProxy).initialize(
            _dao,
            _daoValutAddress,
            bytes("01"), // todo 等合约部署好了，需手动设置
            address(operatorRegistryProxy),
            address(neth),
            address(vnftProxy),
            address(beaconOracleProxy),
            address(depositContract)
        );

        // setLiquidStaking
        neth.setLiquidStaking(address(liquidStakingProxy));
        VNFT(vnftProxy).setLiquidStaking(address(liquidStakingProxy));
        NodeOperatorRegistry(operatorRegistryProxy).setLiquidStaking(address(liquidStakingProxy));
        BeaconOracle(beaconOracleProxy).setLiquidStaking(address(liquidStakingProxy));
        // todo set dao

        vm.stopBroadcast();
    }
}
