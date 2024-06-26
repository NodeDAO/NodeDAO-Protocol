    // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/WithdrawOracle.sol";
import "src/oracles/LargeStakeOracle.sol";
import "src/oracles/MultiHashConsensus.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";

// Goerli settings
abstract contract MainnetHelperContract {
    // _daoEOA is sender
    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

    // ==================== Oracle ====================

    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 _genesisTime = 1606824023;

    uint256 public constant CL_BALANCE = 0;
    uint256 public constant PENDING_BALANCE = 0;

    // oracle member
    address[] memberArray;
    //        address[] memberArray = [
    //            0x143848A303d424FD75995e5827358ba6d30a1801
    //        ];
    uint256 public constant QUORUM = 3;

    // ==================== timelock ====================

    uint256 delayTime = 150;
    address[] proposersArray = [_daoEOA, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc];
    address[] executorsArray = [_daoEOA];

    // ==================== contract set ====================

    address timelock = address(0);

    address liquidStakingProxy = address(0);

    address vaultManagerProxy = address(0);
}

// Goerli settings
abstract contract GoerliHelperContract {
    // _daoEOA is sender
    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

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
    uint256 public constant QUORUM = 2;
    uint256 public constant CL_BALANCE = 416110825088000000000;
    uint256 public constant PENDING_BALANCE = 192000000000000000000;

    // ==================== timelock ====================

    uint256 delayTime = 150;
    address[] proposersArray = [_daoEOA, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc];
    address[] executorsArray = [_daoEOA];

    // ==================== contract set ====================

    address timelock = address(0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb);

    address liquidStakingProxy = address(0x949AC43bb71F8710B0F1193880b338f0323DeB1a);

    address vaultManagerProxy = address(0xb5bE48AE75b1085CBA8d4c16157050d4C9a80Aa0);
}

abstract contract BaseContract {
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    uint256 public constant EPOCHS_PER_FRAME = 225;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 2;

    uint256 public constant EXIT_REQUEST_LIMIT = 100;
    uint256 public constant CL_VAULT_MIN_SETTLE_LIMIT = 1e19;

    WithdrawOracle withdrawOracle;

    LargeStakeOracle largeStakeOracle;

    MultiHashConsensus hashConsensus;

    address hashConsensusProxy;

    address withdrawOracleProxy;

    address largeStakeOracleProxy;

    function deployContracts() public {
        // =============================================
        // deploy implement
        // =============================================

        // deploy MultiHashConsensus implement
        hashConsensus = new MultiHashConsensus();

        // deploy WithdrawOracle implement
        withdrawOracle = new WithdrawOracle();

        // =============================================
        // deploy proxy
        // =============================================

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        // deploy MultiHashConsensus proxy
        hashConsensusProxy = deployer.deploy(address(hashConsensus));
        console.log("========hashConsensusProxy: ", hashConsensusProxy);

        // deploy WithdrawOracle proxy
        withdrawOracleProxy = deployer.deploy(address(withdrawOracle));
        console.log("========withdrawOracleProxy: ", withdrawOracleProxy);
    }

    function initializeContract(address _daoEOA, uint256 _genesisTime, uint256 _clBalance, uint256 _pendingBalance)
        public
    {
        // =============================================
        // initialize contract
        // =============================================

        // initialize MultiHashConsensus
        MultiHashConsensus(hashConsensusProxy).initialize(
            SLOTS_PER_EPOCH, SECONDS_PER_SLOT, _genesisTime, EPOCHS_PER_FRAME, INITIAL_FAST_LANE_LENGTH_SLOTS, _daoEOA
        );

        // initialize WithdrawOracle
        WithdrawOracle(withdrawOracleProxy).initialize(
            SECONDS_PER_SLOT,
            _genesisTime,
            hashConsensusProxy,
            CONSENSUS_VERSION,
            0,
            _daoEOA,
            EXIT_REQUEST_LIMIT,
            CL_VAULT_MIN_SETTLE_LIMIT,
            _clBalance,
            _pendingBalance
        );
    }

    function setContractSettings(
        address[] memory memberArray,
        address _liquidStakingProxy,
        address _vaultManagerProxy,
        uint256 _quorum
    ) public {
        // =============================================
        // configure contract settings
        // =============================================
        // !!! It can be set to a future value after which the contract can be used
        MultiHashConsensus(hashConsensusProxy).updateInitialEpoch(1);

        // withdrawOracleProxy setLiquidStaking
        WithdrawOracle(withdrawOracleProxy).setLiquidStaking(_liquidStakingProxy);

        // withdrawOracleProxy setVaultManager
        WithdrawOracle(withdrawOracleProxy).setVaultManager(_vaultManagerProxy);

        // hashConsensusProxy addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            MultiHashConsensus(hashConsensusProxy).addMember(memberArray[i], _quorum);
        }
    }

    function transferDaoToMultisig(address _daoMultisigContract) public {
        // transfer dao contract

        // withdrawOracleProxy
        WithdrawOracle(withdrawOracleProxy).setDaoAddress(_daoMultisigContract);

        // hashConsensusProxy
        MultiHashConsensus(hashConsensusProxy).setDaoAddress(_daoMultisigContract);
    }

    function transferOwnerToTimelock(address timelock) public {
        // transfer owner to timelock

        // withdrawOracleProxy
        WithdrawOracle(withdrawOracleProxy).transferOwnership(timelock);

        // hashConsensusProxy
        MultiHashConsensus(hashConsensusProxy).transferOwnership(timelock);
    }
}

// export GOERLI_RPC_URL=""
// export PRIVATE_KEY=""
// export ETHERSCAN_API_KEY=""
// --with-gas-price 30000000000
// forge script script/Deploy-oracle.s.sol:DeployGoerliOracleScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify --retries 10 --delay 30
contract DeployGoerliOracleScript is Script, BaseContract, GoerliHelperContract {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployContracts();
        initializeContract(_daoEOA, _genesisTime, CL_BALANCE, PENDING_BALANCE);
        setContractSettings(memberArray, liquidStakingProxy, vaultManagerProxy, QUORUM);
        transferOwnerToTimelock(timelock);

        vm.stopBroadcast();
    }
}

// export GOERLI_RPC_URL=""
// export PRIVATE_KEY=""
// export ETHERSCAN_API_KEY=""
// forge script script/Deploy-oracle.s.sol:DeployMainnetOracleScript  --rpc-url $GOERLI_RPC_URL --broadcast --with-gas-price 30000000000 --verify --retries 10 --delay 30
contract DeployMainnetOracleScript is Script, BaseContract, MainnetHelperContract {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployContracts();
        initializeContract(_daoEOA, _genesisTime, CL_BALANCE, PENDING_BALANCE);
        setContractSettings(memberArray, liquidStakingProxy, vaultManagerProxy, QUORUM);
        transferOwnerToTimelock(timelock);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy-oracle.s.sol:UpgradeWithdrawOracleScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify --retries 10 --delay 30
contract UpgradeWithdrawOracleScript is Script, BaseContract, GoerliHelperContract {
    WithdrawOracle withdrawOracleUpgrade;
    address withdrawOracleUpgradeProxy = address(0x1E726f6111B58e74CCD63d5b659191A49366CaD9);
    MultiHashConsensus multiHashConsensus;
    address multiHashConsensusProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //        withdrawOracleUpgrade = new WithdrawOracle();
        //        console.log("========withdrawOracleUpgrade: ", address(withdrawOracleUpgrade));

        multiHashConsensus = new MultiHashConsensus();

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        multiHashConsensusProxy = deployer.deploy(address(multiHashConsensus));
        console.log("========multiHashConsensusProxy: ", multiHashConsensusProxy);

        // initialize MultiHashConsensus
        MultiHashConsensus(multiHashConsensusProxy).initialize(
            SLOTS_PER_EPOCH, SECONDS_PER_SLOT, _genesisTime, EPOCHS_PER_FRAME, INITIAL_FAST_LANE_LENGTH_SLOTS, _daoEOA
        );

        MultiHashConsensus(multiHashConsensusProxy).updateInitialEpoch(186032);

        // hashConsensusProxy addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            MultiHashConsensus(hashConsensusProxy).addMember(memberArray[i], QUORUM);
        }

        WithdrawOracle(withdrawOracleUpgradeProxy).initializeV2(multiHashConsensusProxy, 5936159);

        MultiHashConsensus(multiHashConsensusProxy).transferOwnership(timelock);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy-oracle.s.sol:DeployGoerliLargeStakeOracleScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify --retries 10 --delay 30
contract DeployGoerliLargeStakeOracleScript is Script, BaseContract, GoerliHelperContract {
    address multiHashConsensusAddress = address(0x9eA34008219d1898269d91b7d04c604CA7324790);
    address largeStakingAddress = address(0xB71D8903Ae22df40DdDb189AfBcE5e99B23b7077);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        largeStakeOracle = new LargeStakeOracle();

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        largeStakeOracleProxy = deployer.deploy(address(largeStakeOracle));
        console.log("========largeStakeOracleProxy: ", largeStakeOracleProxy);

        LargeStakeOracle(largeStakeOracleProxy).initialize(
            SECONDS_PER_SLOT,
            _genesisTime,
            multiHashConsensusAddress,
            CONSENSUS_VERSION,
            0,
            _daoEOA,
            largeStakingAddress
        );

        LargeStakeOracle(largeStakeOracleProxy).transferOwnership(timelock);

        vm.stopBroadcast();
    }
}
