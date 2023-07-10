// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "src/OperatorSlash.sol";
import "forge-std/console.sol";
import "src/largeStaking/ELReward.sol";
import "src/largeStaking/ELRewardFactory.sol";
import "src/largeStaking/LargeStaking.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/VaultManager.sol";
import "src/oracles/WithdrawOracle.sol";
import "src/oracles/LargeStakeOracle.sol";
import "src/oracles/MultiHashConsensus.sol";

// Goerli settings
abstract contract GoerliHelperContractV2 {
    address deployerAddress = 0x7A7df7396A82A5F4eEb7e023C4874c00e8616157;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoMultisigContract = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoVaultContract = 0x4eAd195725669C2213287EC76baab2eBD13ff3b1;

    // goerli: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b
    // mainnet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    address depositContract = 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b;

    address payable operatorRegistryProxy = payable(0x20C43025E44984375c4dC882bFF2016C6E601f0A);
    address payable operatorSlashProxy = payable(0x69b11EF441EEb3A7cb2A3d82bC31F90596A7C48d);

    address timelock = 0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb;

    // oracle
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    uint256 public constant EPOCHS_PER_FRAME = 225;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 2;

    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 _genesisTime = 1616508000;

    // oracle member
    address[] memberArray = [
        0xe583DC38863aB4b5A94da77A6628e2119eaD4B18,
        0x3357c09eCf74C281B6f9CCfAf4D894979349AC4B,
        0x143848A303d424FD75995e5827358ba6d30a1801
    ];
    uint256 public constant QUORUM = 2;

    // ---------------need to modify for deploy------------------
    // need to up
    address withdrawOracleProxy = address(0x1E726f6111B58e74CCD63d5b659191A49366CaD9);
    // @notice !!! initialEpoch is the beacon network current epoch
    uint256 initialEpoch = 186032;
}

// Mainnet settings
abstract contract MainnetHelperContractV2 {
    // https://etherscan.io/address/0x178b7401c32a4aab5ef128458888779eaaf4e78a
    address deployerAddress = 0x178B7401C32A4aab5EF128458888779eaAF4E78a;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0xeF76D4e75154739F75F6068b3470c7968cC3Fcd1;
    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;
    address _daoVaultContract = 0x79285fd2224cBC0b25065C49537b72c1a4567AFC;

    // goerli: 0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b
    // mainnet: 0x00000000219ab540356cBB839Cbe05303d7705Fa
    address depositContract = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

    address payable operatorSlashProxy = payable(0x82c87cC83c9fA09DAdBEBFB8f8b9152Ee6104B5d);
    address payable operatorRegistryProxy = payable(0x8742178Ac172eC7235E54808d5F327C30A51c492);

    address timelock = 0x16F692525f3b8c8a96F8c945D365Da958Fb5735B;

    // oracle
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    uint256 public constant EPOCHS_PER_FRAME = 225;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 2;

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
    uint256 public constant QUORUM = 2;

    // ---------------need to modify for deploy------------------

    // need to up
    address withdrawOracleProxy = address(0x2B74f97aDC698b571C2F046673Fd5Cd028673c41);
    // @notice initialEpoch is the beacon network current epoch
    uint256 initialEpoch = 186032;
}

contract GoerliDeployLargeStakingScript is Script, GoerliHelperContractV2 {
    ELReward eLRewardContract;
    OperatorSlash operatorSlashContract;
    NodeOperatorRegistry nodeOperatorRegistryContract;
    VaultManager vaultManagerContract;
    WithdrawOracle withdrawOracleContract;

    ELRewardFactory eLRewardFactoryContract;
    address eLRewardFactoryContractProxy;

    LargeStaking largeStakingContract;
    address largeStakingContractProxy;

    MultiHashConsensus multiHashConsensus;
    address multiHashConsensusProxy;

    LargeStakeOracle largeStakeOracle;
    address largeStakeOracleProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy
        operatorSlashContract = new OperatorSlash();
        nodeOperatorRegistryContract = new NodeOperatorRegistry();
        eLRewardContract = new ELReward();
        vaultManagerContract = new VaultManager();
        withdrawOracleContract = new WithdrawOracle();

        eLRewardFactoryContract = new ELRewardFactory();
        eLRewardFactoryContractProxy = deployer.deploy(address(eLRewardFactoryContract));

        largeStakingContract = new LargeStaking();
        largeStakingContractProxy = deployer.deploy(address(largeStakingContract));

        multiHashConsensus = new MultiHashConsensus();
        multiHashConsensusProxy = deployer.deploy(address(multiHashConsensus));

        largeStakeOracle = new LargeStakeOracle();
        largeStakeOracleProxy = deployer.deploy(address(largeStakeOracle));

        // initialize
        ELRewardFactory(eLRewardFactoryContractProxy).initialize(address(eLRewardContract), _daoEOA);

        LargeStaking(largeStakingContractProxy).initialize(
            _daoEOA,
            _daoVaultContract,
            operatorRegistryProxy,
            operatorSlashProxy,
            largeStakeOracleProxy,
            eLRewardFactoryContractProxy,
            depositContract
        );

        MultiHashConsensus(multiHashConsensusProxy).initialize(
            SLOTS_PER_EPOCH, SECONDS_PER_SLOT, _genesisTime, EPOCHS_PER_FRAME, INITIAL_FAST_LANE_LENGTH_SLOTS, _daoEOA
        );

        MultiHashConsensus(multiHashConsensusProxy).updateInitialEpoch(initialEpoch);

        // hashConsensusProxy addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            MultiHashConsensus(multiHashConsensusProxy).addMember(memberArray[i], QUORUM);
        }

        MultiHashConsensus(multiHashConsensusProxy).addReportProcessor(withdrawOracleProxy, 2);
        MultiHashConsensus(multiHashConsensusProxy).addReportProcessor(largeStakeOracleProxy, 2);

        MultiHashConsensus(multiHashConsensusProxy).transferOwnership(timelock);

        LargeStakeOracle(largeStakeOracleProxy).initialize(
            SECONDS_PER_SLOT,
            _genesisTime,
            multiHashConsensusProxy,
            CONSENSUS_VERSION,
            0,
            _daoEOA,
            largeStakingContractProxy
        );

        LargeStakeOracle(largeStakeOracleProxy).transferOwnership(timelock);

        // upgrade contract
        console.log("=========operatorSlashContract===========", address(operatorSlashContract));
        console.log("=========vaultManagerContract===========", address(vaultManagerContract));
        console.log("=========nodeOperatorRegistryContract===========", address(nodeOperatorRegistryContract));
        console.log("=========withdrawOracleContract=========", address(withdrawOracleContract));

        // new contract
        console.log("=========eLRewardContract===========", address(eLRewardContract));
        console.log("=========eLRewardFactoryContract===========", address(eLRewardFactoryContract));
        console.log("=========eLRewardFactoryContractProxy===========", address(eLRewardFactoryContractProxy));
        console.log("=========largeStakingContract===========", address(largeStakingContract));
        console.log("=========largeStakingContractProxy===========", address(largeStakingContractProxy));
        console.log("========multiHashConsensusProxy===========", multiHashConsensusProxy);
        console.log("========largeStakeOracleProxy===========", largeStakeOracleProxy);

        vm.stopBroadcast();
    }
}

contract MainnetDeployLargeStakingScript is Script, MainnetHelperContractV2 {
    ELReward eLRewardContract;
    OperatorSlash operatorSlashContract;
    NodeOperatorRegistry nodeOperatorRegistryContract;
    VaultManager vaultManagerContract;
    WithdrawOracle withdrawOracleContract;

    ELRewardFactory eLRewardFactoryContract;
    address eLRewardFactoryContractProxy;

    LargeStaking largeStakingContract;
    address largeStakingContractProxy;

    MultiHashConsensus multiHashConsensus;
    address multiHashConsensusProxy;

    LargeStakeOracle largeStakeOracle;
    address largeStakeOracleProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy
        operatorSlashContract = new OperatorSlash();
        nodeOperatorRegistryContract = new NodeOperatorRegistry();
        eLRewardContract = new ELReward();
        vaultManagerContract = new VaultManager();
        withdrawOracleContract = new WithdrawOracle();

        eLRewardFactoryContract = new ELRewardFactory();
        eLRewardFactoryContractProxy = deployer.deploy(address(eLRewardFactoryContract));

        largeStakingContract = new LargeStaking();
        largeStakingContractProxy = deployer.deploy(address(largeStakingContract));

        multiHashConsensus = new MultiHashConsensus();
        multiHashConsensusProxy = deployer.deploy(address(multiHashConsensus));

        largeStakeOracle = new LargeStakeOracle();
        largeStakeOracleProxy = deployer.deploy(address(largeStakeOracle));

        // initialize
        ELRewardFactory(eLRewardFactoryContractProxy).initialize(address(eLRewardContract), _daoMultisigContract);

        LargeStaking(largeStakingContractProxy).initialize(
            _daoMultisigContract,
            _daoVaultContract,
            operatorRegistryProxy,
            operatorSlashProxy,
            largeStakeOracleProxy,
            eLRewardFactoryContractProxy,
            depositContract
        );

        MultiHashConsensus(multiHashConsensusProxy).initialize(
            SLOTS_PER_EPOCH, SECONDS_PER_SLOT, _genesisTime, EPOCHS_PER_FRAME, INITIAL_FAST_LANE_LENGTH_SLOTS, _daoMultisigContract
        );

        MultiHashConsensus(multiHashConsensusProxy).updateInitialEpoch(initialEpoch);

        // hashConsensusProxy addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            MultiHashConsensus(multiHashConsensusProxy).addMember(memberArray[i], QUORUM);
        }

        MultiHashConsensus(multiHashConsensusProxy).addReportProcessor(withdrawOracleProxy, 2);
        MultiHashConsensus(multiHashConsensusProxy).addReportProcessor(largeStakeOracleProxy, 2);

        MultiHashConsensus(multiHashConsensusProxy).transferOwnership(timelock);

        LargeStakeOracle(largeStakeOracleProxy).initialize(
            SECONDS_PER_SLOT,
            _genesisTime,
            multiHashConsensusProxy,
            CONSENSUS_VERSION,
            0,
            _daoMultisigContract,
            largeStakingContractProxy
        );

        LargeStakeOracle(largeStakeOracleProxy).transferOwnership(timelock);

        // upgrade contract
        console.log("=========operatorSlashContract===========", address(operatorSlashContract));
        console.log("=========vaultManagerContract===========", address(vaultManagerContract));
        console.log("=========nodeOperatorRegistryContract===========", address(nodeOperatorRegistryContract));
        console.log("=========withdrawOracleContract=========", address(withdrawOracleContract));

        // new contract
        console.log("=========eLRewardContract===========", address(eLRewardContract));
        console.log("=========eLRewardFactoryContract===========", address(eLRewardFactoryContract));
        console.log("=========eLRewardFactoryContractProxy===========", address(eLRewardFactoryContractProxy));
        console.log("=========largeStakingContract===========", address(largeStakingContract));
        console.log("=========largeStakingContractProxy===========", address(largeStakingContractProxy));
        console.log("========multiHashConsensusProxy===========", multiHashConsensusProxy);
        console.log("========largeStakeOracleProxy===========", largeStakeOracleProxy);

        vm.stopBroadcast();
    }
}