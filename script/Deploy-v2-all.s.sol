// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/WithdrawOracle.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/vault/ELVault.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/NodeDaoTreasury.sol";
import "src/OperatorSlash.sol";
import "src/WithdrawalRequest.sol";
import "src/vault/VaultManager.sol";
import "src/oracles/HashConsensus.sol";
import "forge-std/console.sol";

// Goerli settings
abstract contract GoerliHelperContractV2 {
    address deployerAddress = 0x7A7df7396A82A5F4eEb7e023C4874c00e8616157;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoMultisigContract = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

    address timelock = 0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb;

    address payable liquidStakingProxy = payable(0x949AC43bb71F8710B0F1193880b338f0323DeB1a);
    address payable operatorRegistryProxy = payable(0x20C43025E44984375c4dC882bFF2016C6E601f0A);
    address payable vnftProxy = payable(0x3CB42bb75Cf1BcC077010ac1E3d3Be22D13326FA);
    address payable neth = payable(0x408F53a38db844B167B66f001fDc49613E25eC78);
    address payable consensusVaultProxy = payable(0x138d5D3C2d7d68bFC653726c8a5E8bA301452202);

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
    uint256 public constant CL_BALANCE = 0;
    uint256 public constant PENDING_BALANCE = 0;
}

// Mainnet settings
abstract contract MainnetHelperContractV2 {
    // https://etherscan.io/address/0x178b7401c32a4aab5ef128458888779eaaf4e78a
    address deployerAddress = 0x178B7401C32A4aab5EF128458888779eaAF4E78a;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0xeF76D4e75154739F75F6068b3470c7968cC3Fcd1;
    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;

    address timelock = 0x16F692525f3b8c8a96F8c945D365Da958Fb5735B;

    address payable liquidStakingProxy = payable(0x8103151E2377e78C04a3d2564e20542680ed3096);
    address payable operatorRegistryProxy = payable(0x8742178Ac172eC7235E54808d5F327C30A51c492);
    address payable vnftProxy = payable(0x58553F5c5a6AEE89EaBFd42c231A18aB0872700d);
    address payable neth = payable(0xC6572019548dfeBA782bA5a2093C836626C7789A);
    address payable consensusVaultProxy = payable(0x4b8Dc35b44296D8D6DCc7aFEBBbe283c997E80Ae);

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

    uint256 public constant QUORUM = 3;
    // https://etherscan.io/address/0x503525159C0174C7758fe3D6C8eeCC595768a7A1#readProxyContract
    uint256 public constant CL_BALANCE = 833769315153000000000;
    uint256 public constant PENDING_BALANCE = 0;
}

contract GoerliDeployNodeDaoTreasury is Script, GoerliHelperContractV2 {
    NodeDaoTreasury nodeDaoTreasury;
    address payable nodeDaoTreasuryProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury();
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        nodeDaoTreasuryProxy = payable(deployer.deploy(address(nodeDaoTreasury)));
        console.log("===============nodeDaoTreasuryProxy=================", address(nodeDaoTreasuryProxy));

        NodeDaoTreasury(nodeDaoTreasuryProxy).initialize(_daoMultisigContract);
        NodeDaoTreasury(nodeDaoTreasuryProxy).transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
}

contract MainnetDeployNodeDaoTreasury is Script, MainnetHelperContractV2 {
    NodeDaoTreasury nodeDaoTreasury;
    address payable nodeDaoTreasuryProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury();
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        nodeDaoTreasuryProxy = payable(deployer.deploy(address(nodeDaoTreasury)));
        console.log("===============nodeDaoTreasuryProxy=================", address(nodeDaoTreasuryProxy));

        NodeDaoTreasury(nodeDaoTreasuryProxy).initialize(_daoMultisigContract);
        NodeDaoTreasury(nodeDaoTreasuryProxy).transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
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

    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;
    VaultManager vaultManager;
    WithdrawOracle withdrawOracle;
    HashConsensus hashConsensus;

    address operatorSlashProxy;
    address withdrawalRequestProxy;
    address vaultManagerProxy;
    address withdrawOracleProxy;
    address hashConsensusProxy;

    function deployContracts(DeployProxy deployer) public {
        operatorSlash = new OperatorSlash();
        console.log("===============operatorSlash=================", address(operatorSlash));

        withdrawalRequest = new WithdrawalRequest();
        console.log("===============withdrawalRequest=================", address(withdrawalRequest));

        vaultManager = new VaultManager();
        console.log("===============vaultManager=================", address(vaultManager));

        hashConsensus = new HashConsensus();
        console.log("===============hashConsensus=================", address(hashConsensus));

        withdrawOracle = new WithdrawOracle();
        console.log("===============withdrawOracle=================", address(withdrawOracle));

        operatorSlashProxy = deployer.deploy(address(operatorSlash));
        console.log("===============operatorSlashProxy=================", address(operatorSlashProxy));

        withdrawalRequestProxy = deployer.deploy(address(withdrawalRequest));
        console.log("===============withdrawalRequestProxy=================", address(withdrawalRequestProxy));

        vaultManagerProxy = deployer.deploy(address(vaultManager));
        console.log("===============vaultManagerProxy=================", address(vaultManagerProxy));

        hashConsensusProxy = deployer.deploy(address(hashConsensus));
        console.log("===============hashConsensusProxy=================", hashConsensusProxy);

        withdrawOracleProxy = deployer.deploy(address(withdrawOracle));
        console.log("===============withdrawOracleProxy=================", withdrawOracleProxy);
    }

    function initializeOracleContract(
        address _daoEOA,
        uint256 _genesisTime,
        uint256 _clBalance,
        uint256 _pendingBalance
    ) public {
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
        console.log("======initializeOracleContract=======", _daoEOA);
        console.log("======hashConsensusProxy=======", HashConsensus(hashConsensusProxy).dao());

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
        HashConsensus(hashConsensusProxy).updateInitialEpoch(1);

        // withdrawOracleProxy setLiquidStaking
        WithdrawOracle(withdrawOracleProxy).setLiquidStaking(_liquidStakingProxy);

        // withdrawOracleProxy setVaultManager
        WithdrawOracle(withdrawOracleProxy).setVaultManager(_vaultManagerProxy);

        // hashConsensusProxy addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            HashConsensus(hashConsensusProxy).addMember(memberArray[i], _quorum);
        }
    }

    function initializeOtherContract(
        address dao,
        address liquidStakingProxy,
        address vnftProxy,
        address operatorRegistryProxy,
        address neth,
        uint256 _delayedExitSlashStandard
    ) public {
        OperatorSlash(operatorSlashProxy).initialize(
            dao,
            liquidStakingProxy,
            vnftProxy,
            operatorRegistryProxy,
            withdrawalRequestProxy,
            vaultManagerProxy,
            _delayedExitSlashStandard
        );

        WithdrawalRequest(withdrawalRequestProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, neth, operatorRegistryProxy, vaultManagerProxy
        );

        VaultManager(vaultManagerProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, operatorRegistryProxy, withdrawOracleProxy, operatorSlashProxy
        );
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

        WithdrawOracle(withdrawOracleProxy).transferOwnership(timelock);

        HashConsensus(hashConsensusProxy).transferOwnership(timelock);

        OperatorSlash(operatorSlashProxy).transferOwnership(timelock);

        WithdrawalRequest(withdrawalRequestProxy).transferOwnership(timelock);

        VaultManager(vaultManagerProxy).transferOwnership(timelock);
    }
}

contract GoerliDeployNewContractScript is Script, GoerliHelperContractV2, BaseContract {
    function setUp() public {}

    function run() public {
        deployContracts(deployer);
        initializeOracleContract(_daoEOA, _genesisTime, CL_BALANCE, PENDING_BALANCE);
        initializeOtherContract(_daoMultisigContract, liquidStakingProxy, vnftProxy, operatorRegistryProxy, neth, 7200);
        setContractSettings(memberArray, liquidStakingProxy, vaultManagerProxy, QUORUM);
        transferOwnerToTimelock(timelock);
    }
}

contract MainnetDeployNewContractScript is Script, MainnetHelperContractV2, BaseContract {
    function setUp() public {}

    function run() public {
        deployContracts(deployer);
        initializeOracleContract(_daoEOA, _genesisTime, CL_BALANCE, PENDING_BALANCE);
        initializeOtherContract(_daoMultisigContract, liquidStakingProxy, vnftProxy, operatorRegistryProxy, neth, 50400);
        setContractSettings(memberArray, liquidStakingProxy, vaultManagerProxy, QUORUM);
        transferDaoToMultisig(_daoMultisigContract);
        transferOwnerToTimelock(timelock);
    }
}
