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
import "src/TimelockController.sol";

// Goerli settings
abstract contract GoerliHelperContract {
    // _daoEOA is sender
    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoValutAddress = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

    // goerli: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b
    // mainnet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    address depositContract = 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b;

    // ==================== Oracle ====================

    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 _genesisTime = 1616508000;
    // oracle member
    address[] memberArray = [
        0xe583DC38863aB4b5A94da77A6628e2119eaD4B18,
        0x3357c09eCf74C281B6f9CCfAf4D894979349AC4B,
        0x143848A303d424FD75995e5827358ba6d30a1801
    ];

    // ==================== timelock ====================

    uint256 delayTime = 150;
    address[] proposersArray = [_daoEOA, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc];
    address[] executorsArray = [_daoEOA];
}

// Mainnet settings
abstract contract MainnetHelperContract {
    // _daoEOA is sender
    address _daoEOA = 0xeF76D4e75154739F75F6068b3470c7968cC3Fcd1;
    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;
    address _daoValutAddress = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;

    // goerli: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b
    // mainnet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    address depositContract = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    // ==================== Oracle ====================

    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 _genesisTime = 1606824023;
    // oracle member
    address[] memberArray = [
        0x080C185D164446746068Db1650850F453ffdB92c,
        0xad7457910Ba258904cFe9B676a68201455CE6e61,
        0xf4A30Ec717b7F3aCC7fAeD373C941086a292BD5E,
        0x22E0cAF2B2dD1E11602D58eEfE9865f80aA949c6
    ];
    // ==================== timelock ====================

    uint256 delayTime = 86400;
    address[] proposersArray =
        [_daoMultisigContract, 0x3E29BF7B650b8910F3B4DDda5b146e8716c683a6, 0xeF76D4e75154739F75F6068b3470c7968cC3Fcd1];
    address[] executorsArray = [_daoMultisigContract];
}

abstract contract BaseContract {
    TimelockController timelock;

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

    function deployContracts(uint256 delayTime, address[] memory proposersArray, address[] memory executorsArray)
        public
    {
        // =============================================
        // deploy implement
        // =============================================

        // deploy timelock
        // timelock: admin is address(0), self administration
        timelock = new TimelockController(delayTime, proposersArray, executorsArray, address(0));

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

        // =============================================
        // deploy proxy
        // =============================================

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        // deploy ConsensusVault proxy
        consensusVaultProxy = payable(deployer.deploy(address(consensusVault)));
        console.log("========consensusVaultProxy: ", consensusVaultProxy);

        // deploy vNFT proxy
        vnftProxy = deployer.deploy(address(vnft));
        console.log("========vnftProxy: ", vnftProxy);

        // deploy ELVaultFactory proxy
        vaultFactoryContractProxy = deployer.deploy(address(vaultFactoryContract));
        console.log("========vaultFactoryContractProxy: ", vaultFactoryContractProxy);

        // deploy NodeOperatorRegistry proxy
        operatorRegistryProxy = deployer.deploy(address(operatorRegistry));
        console.log("========operatorRegistryProxy: ", operatorRegistryProxy);

        // deploy BeaconOracle proxy
        beaconOracleProxy = deployer.deploy(address(beaconOracle));
        console.log("========beaconOracleProxy: ", beaconOracleProxy);

        // deploy LiquidStaking proxy
        liquidStakingProxy = payable(deployer.deploy(address(liquidStaking)));
        console.log("========liquidStakingProxy: ", liquidStakingProxy);
    }

    function initializeContract(
        address _daoEOA,
        address _daoValutAddress,
        address depositContract,
        uint256 _genesisTime
    ) public {
        // =============================================
        // initialize contract
        // =============================================

        // neth contract does not require initialization

        // initialize VNFT
        VNFT(vnftProxy).initialize();

        // initialize ConsensusVault
        ConsensusVault(consensusVaultProxy).initialize(_daoEOA, address(liquidStakingProxy));

        // ELVault contract does not require initialization

        // initialize ELVaultFactory
        ELVaultFactory(vaultFactoryContractProxy).initialize(
            address(vaultContract), address(vnftProxy), address(liquidStakingProxy), _daoEOA
        );

        // initialize NodeOperatorRegistry
        NodeOperatorRegistry(operatorRegistryProxy).initialize(
            _daoEOA, _daoValutAddress, address(vaultFactoryContractProxy), address(vnftProxy)
        );

        // initialize BeaconOracle
        BeaconOracle(beaconOracleProxy).initialize(_daoEOA, _genesisTime, address(vnftProxy));

        bytes memory withdrawalCredentials =
            bytes.concat(hex"010000000000000000000000", abi.encodePacked(consensusVaultProxy));
        console.log("========withdrawalCredentials========");
        console.logBytes(withdrawalCredentials);

        // initialize LiquidStaking
        LiquidStaking(liquidStakingProxy).initialize(
            _daoEOA,
            _daoValutAddress,
            withdrawalCredentials,
            address(operatorRegistryProxy),
            address(neth),
            address(vnftProxy),
            address(beaconOracleProxy),
            depositContract
        );
    }

    function setContractSettings(address[] memory memberArray) public {
        // =============================================
        // configure contract settings
        // =============================================

        // ELVaultFactory setNodeOperatorRegistry
        ELVaultFactory(vaultFactoryContractProxy).setNodeOperatorRegistry(address(operatorRegistryProxy));

        // neth setLiquidStaking
        neth.setLiquidStaking(address(liquidStakingProxy));

        // VNFT setLiquidStaking
        VNFT(vnftProxy).setLiquidStaking(address(liquidStakingProxy));

        // NodeOperatorRegistry setLiquidStaking
        NodeOperatorRegistry(operatorRegistryProxy).setLiquidStaking(address(liquidStakingProxy));

        // BeaconOracle setLiquidStaking
        BeaconOracle(beaconOracleProxy).setLiquidStaking(address(liquidStakingProxy));

        // BeaconOracle addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            BeaconOracle(beaconOracleProxy).addOracleMember(memberArray[i]);
        }
    }

    function transferDaoToMultisig(address _daoMultisigContract) public {
        // transfer dao contract

        // ConsensusVault
        ConsensusVault(consensusVaultProxy).setDaoAddress(_daoMultisigContract);

        // ELVaultFactory
        ELVaultFactory(vaultFactoryContractProxy).setDaoAddress(_daoMultisigContract);

        // NodeOperatorRegistry
        NodeOperatorRegistry(operatorRegistryProxy).setDaoAddress(_daoMultisigContract);

        // BeaconOracle
        BeaconOracle(beaconOracleProxy).setDaoAddress(_daoMultisigContract);

        // LiquidStaking
        LiquidStaking(liquidStakingProxy).setDaoAddress(_daoMultisigContract);
    }

    function transferOwnerToTimelock() public {
        // transfer owner to timelock

        // ConsensusVault
        ConsensusVault(consensusVaultProxy).transferOwnership(address(timelock));

        // neth
        neth.transferOwnership(address(timelock));

        // nft
        VNFT(vnftProxy).transferOwnership(address(timelock));

        // ELVaultFactory
        ELVaultFactory(vaultFactoryContractProxy).transferOwnership(address(timelock));

        // UpgradeableBeacon
        address payable upgradeableBeacon = payable(ELVaultFactory(vaultFactoryContractProxy).beacon());
        console.log("========upgradeableBeacon: ", upgradeableBeacon);
        UpgradeableBeacon(upgradeableBeacon).transferOwnership(address(timelock));

        // NodeOperatorRegistry
        NodeOperatorRegistry(operatorRegistryProxy).transferOwnership(address(timelock));

        // BeaconOracle
        BeaconOracle(beaconOracleProxy).transferOwnership(address(timelock));

        // LiquidStaking
        LiquidStaking(liquidStakingProxy).transferOwnership(address(timelock));
    }
}

// export GOERLI_RPC_URL=""
// export PRIVATE_KEY=""
// export ETHERSCAN_API_KEY=""
// forge script script/Deploy-all.s.sol:DeployGolierScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify
contract DeployGolierScript is Script, BaseContract, GoerliHelperContract {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployContracts(delayTime, proposersArray, executorsArray);
        initializeContract(_daoEOA, _daoValutAddress, depositContract, _genesisTime);
        setContractSettings(memberArray);
        transferOwnerToTimelock();

        vm.stopBroadcast();
    }
}

// export MAINNET_RPC_URL=""
// export PRIVATE_KEY=""
// export ETHERSCAN_API_KEY=""
// forge script script/Deploy-all.s.sol:DeployMainnetScript  --rpc-url $MAINNET_RPC_URL --broadcast --verify
contract DeployMainnetScript is Script, BaseContract, MainnetHelperContract {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        deployContracts(delayTime, proposersArray, executorsArray);
        initializeContract(_daoEOA, _daoValutAddress, depositContract, _genesisTime);
        setContractSettings(memberArray);
        transferDaoToMultisig(_daoMultisigContract);
        transferOwnerToTimelock();
        vm.stopBroadcast();
    }
}
