import "src/oracles/WithdrawOracle.sol";
import "src/oracles/LargeStakeOracle.sol";
import "src/oracles/MultiHashConsensus.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./utils/DeployProxy.sol";

// forge script script/Deploy-oracle-v2.s.sol:DeployGoerliMultiHashConsensusScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify --retries 10 --delay 30
contract DeployGoerliMultiHashConsensusScript is Script {
    address withdrawOracleProxyAddress = address(0x1E726f6111B58e74CCD63d5b659191A49366CaD9);
    address largeStakeOracleProxyAddress = address(0xB8E0EE431d78273d7BAefEB0Fb64897626b0B8FA);
    MultiHashConsensus multiHashConsensus;
    address multiHashConsensusProxy;

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

    // ==================== timelock ====================

    uint256 delayTime = 150;
    address[] proposersArray = [_daoEOA, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc];
    address[] executorsArray = [_daoEOA];

    // ==================== contract set ====================

    address timelock = address(0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb);

    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    uint256 public constant EPOCHS_PER_FRAME = 225;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 2;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        multiHashConsensus = new MultiHashConsensus();

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        multiHashConsensusProxy = deployer.deploy(address(multiHashConsensus));
        console.log("========multiHashConsensusProxy: ", multiHashConsensusProxy);

        // initialize MultiHashConsensus
        MultiHashConsensus(multiHashConsensusProxy).initialize(
            SLOTS_PER_EPOCH, SECONDS_PER_SLOT, _genesisTime, EPOCHS_PER_FRAME, INITIAL_FAST_LANE_LENGTH_SLOTS, _daoEOA
        );

        MultiHashConsensus(multiHashConsensusProxy).updateInitialEpoch(186932);
        MultiHashConsensus(multiHashConsensusProxy).addReportProcessor(withdrawOracleProxyAddress, 2);
        MultiHashConsensus(multiHashConsensusProxy).addReportProcessor(largeStakeOracleProxyAddress, 2);

        // hashConsensusProxy addOracleMember
        for (uint256 i = 0; i < memberArray.length; ++i) {
            MultiHashConsensus(multiHashConsensusProxy).addMember(memberArray[i], QUORUM);
        }

        MultiHashConsensus(multiHashConsensusProxy).transferOwnership(timelock);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy-oracle-v2.s.sol:DeployImplScript  --rpc-url $GOERLI_RPC_URL --broadcast --verify --retries 10 --delay 30
contract DeployImplScript is Script {
    WithdrawOracle withdrawOracle;
    MultiHashConsensus multiHashConsensus;
    LargeStakeOracle largeStakeOracle;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //        multiHashConsensus = new MultiHashConsensus();
        //        console.log("========multiHashConsensus impl: ", address(multiHashConsensus));

        //        withdrawOracle = new WithdrawOracle();
        //        console.log("========withdrawOracle impl: ", address(withdrawOracle));
        //
        largeStakeOracle = new LargeStakeOracle();
        console.log("========largeStakeOracle impl: ", address(largeStakeOracle));

        vm.stopBroadcast();
    }
}
