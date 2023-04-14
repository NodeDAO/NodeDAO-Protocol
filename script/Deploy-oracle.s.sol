    // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/WithdrawOracle.sol";
import "src/oracles/HashConsensus.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";

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

    // ==================== timelock ====================

    uint256 delayTime = 150;
    address[] proposersArray = [_daoEOA, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc];
    address[] executorsArray = [_daoEOA];

    // ==================== contract ====================

    address timelock = address(0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb);

    address liquidStakingProxy = address(0xa8256fD3A31648D49D0f3551e6e45Db6f5f91d53);

    address vaultManagerProxy = address(0x0dfb3d69aeC85892d4e5CDd7Ad431B2C50b0E358);
}

abstract contract BaseContract {
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    uint256 public constant EPOCHS_PER_FRAME = 225;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 1;

    uint256 public constant EXIT_REQUEST_LIMIT = 100;
    uint256 public constant CL_VAULT_MIN_SETTLE_LIMIT = 1e19;

    uint256 public constant CL_BALANCE = 1e19;
    uint256 public constant PENDING_BALANCE = 1e19;

    WithdrawOracle withdrawOracle;

    HashConsensus hashConsensus;

    address hashConsensusProxy;

    address withdrawOracleProxy;

    function deployContracts() public {
        // =============================================
        // deploy implement
        // =============================================

        // deploy HashConsensus implement
        hashConsensus = new HashConsensus();

        // deploy WithdrawOracle implement
        withdrawOracle = new WithdrawOracle();

        // =============================================
        // deploy proxy
        // =============================================

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        // deploy HashConsensus proxy
        hashConsensusProxy = deployer.deploy(address(hashConsensus));
        console.log("========hashConsensusProxy: ", hashConsensusProxy);

        // deploy WithdrawOracle proxy
        withdrawOracleProxy = deployer.deploy(address(withdrawOracle));
        console.log("========withdrawOracleProxy: ", withdrawOracleProxy);
    }

    function initializeContract(address _daoEOA, uint256 _genesisTime) public {
        // =============================================
        // initialize contract
        // =============================================

        // initialize HashConsensus
        HashConsensus(hashConsensusProxy).initialize(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT,
            _genesisTime,
            EPOCHS_PER_FRAME,
            INITIAL_FAST_LANE_LENGTH_SLOTS,
            _daoEOA,
            withdrawOracleProxy
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
            CL_BALANCE,
            PENDING_BALANCE
        );
    }

    function setContractSettings(address[] memory memberArray, address _liquidStakingProxy, address _vaultManagerProxy)
        public
    {
        // =============================================
        // configure contract settings
        // =============================================

        // withdrawOracleProxy setLiquidStaking
        WithdrawOracle(withdrawOracleProxy).setLiquidStaking(_liquidStakingProxy);

        // withdrawOracleProxy setVaultManager
        WithdrawOracle(withdrawOracleProxy).setVaultManager(_vaultManagerProxy);

        // hashConsensusProxy addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            HashConsensus(hashConsensusProxy).addMember(memberArray[i], 2);
        }
    }

    function transferDaoToMultisig(address _daoMultisigContract) public {
        // transfer dao contract

        // withdrawOracleProxy
        WithdrawOracle(withdrawOracleProxy).setDaoAddress(_daoMultisigContract);

        // hashConsensusProxy
        HashConsensus(hashConsensusProxy).setDaoAddress(_daoMultisigContract);
    }

    function transferOwnerToTimelock(address timelock) public {
        // transfer owner to timelock

        // withdrawOracleProxy
        WithdrawOracle(withdrawOracleProxy).transferOwnership(timelock);

        // hashConsensusProxy
        HashConsensus(hashConsensusProxy).transferOwnership(timelock);
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
        initializeContract(_daoEOA, _genesisTime);
        setContractSettings(memberArray, liquidStakingProxy, vaultManagerProxy);
        transferOwnerToTimelock(timelock);

        vm.stopBroadcast();
    }
}
