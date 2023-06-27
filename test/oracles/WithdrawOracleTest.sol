// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "test/helpers/oracles/MultiHashConsensusWithTimer.sol";
import "test/helpers/oracles/MockMultiOracleProvider.sol";
import "test/helpers/oracles/WithdrawOracleWithTimer.sol";
import "src/LiquidStaking.sol";
import "src/vault/VaultManager.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/vault/ELVault.sol";
import "src/vault/VaultManager.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/ConsensusVault.sol";
import "src/OperatorSlash.sol";
import "src/WithdrawalRequest.sol";
import "src/largeStaking/LargeStaking.sol";
import "src/largeStaking/ELReward.sol";
import "src/largeStaking/ELRewardFactory.sol";
import "src/utils/Array.sol";

// forge test --match-path  test/oracles/WithdrawOracleTest.sol
contract WithdrawOracleTest is Test, MockMultiOracleProvider {
    using SafeCast for uint256;

    MultiHashConsensusWithTimer consensus;
    WithdrawOracleWithTimer withdrawOracle;
    MockMultiReportProcessor reportProcessor1;

    address USER_1 = address(0xe583DC38863aB4b5A94da77A6628e2119eaD4B18);
    address withdrawalAddress = address(0x3357c09eCf74C281B6f9CCfAf4D894979349AC4B);

    ////////////////////////////////////////////////////////////////
    //------------ init and set other contracts --------------------
    ////////////////////////////////////////////////////////////////
    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    VaultManager vaultManager;
    NodeOperatorRegistry operatorRegistry;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    ConsensusVault consensusVaultContract;
    address payable consensusVaultContractAddr;
    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;
    LargeStaking largeStaking;
    ELReward elReward;
    ELRewardFactory elRewardFactor;

    address _dao = DAO;
    address _daoValutAddress = address(2);
    address _rewardAddress = address(3);
    address _controllerAddress = address(1000);
    address _controllerAddress2 = address(1001);
    address[] _rewardAddresses = new address[] (1);
    uint256[] _ratios = new uint256[] (1);
    uint256 moduleId = 1;

    function initAndSetOtherContract() public {
        _rewardAddresses[0] = address(5);
        _ratios[0] = 100;
        liquidStaking = new LiquidStaking();

        consensusVaultContract = new ConsensusVault();
        consensusVaultContract.initialize(_dao, address(liquidStaking));
        consensusVaultContractAddr = payable(consensusVaultContract);

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();
        vaultFactoryContract = new ELVaultFactory();
        vaultFactoryContract.initialize(address(vaultContract), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress, address(vaultFactoryContract), address(vnft));
        vm.prank(_dao);
        operatorRegistry.setNodeOperatorregistrySetting(
            address(0), address(0), address(liquidStaking), address(0), address(0), 0, 0, 0
        );
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

        depositContract = new DepositContract();

        liquidStaking.initialize(
            _dao,
            _daoValutAddress,
            hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106",
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(withdrawOracle),
            address(depositContract)
        );

        vm.prank(_dao);
        liquidStaking.setOperatorCanLoanAmounts(32 ether);

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "one", _controllerAddress, address(4), _rewardAddresses, _ratios
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        vaultManager = new VaultManager();

        uint256[] memory _operatorIds = new uint256[](0);
        address[] memory _users = new address[](0);
        uint256[] memory _nethAmounts = new uint256[](0);

        withdrawalRequest = new WithdrawalRequest();
        withdrawalRequest.initialize(
            _dao, address(liquidStaking), address(vnft), address(neth), address(operatorRegistry), address(vaultManager)
        );

        operatorSlash = new OperatorSlash();
        operatorSlash.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawalRequest),
            address(vaultManager),
            7200
        );

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorregistrySetting(
            address(0), address(0), address(0), address(operatorSlash), address(0), 0, 0, 0
        );
        vm.prank(_dao);
        liquidStaking.initializeV2(
            _operatorIds,
            _users,
            _nethAmounts,
            address(consensusVaultContract),
            address(vaultManager),
            address(withdrawalRequest),
            address(operatorSlash),
            address(withdrawOracle)
        );

        vaultManager.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawOracle),
            address(operatorSlash)
        );

        elReward = new ELReward();
        elRewardFactor = new ELRewardFactory();
        elRewardFactor.initialize(address(elReward), _dao);
        largeStaking = new LargeStaking();
        largeStaking.initialize(
            _dao,
            _daoValutAddress,
            address(operatorRegistry),
            address(withdrawOracle),
            address(elRewardFactor),
            address(depositContract),
            address(operatorSlash)
        );
        vm.prank(_dao);
        operatorRegistry.initializeV3(address(largeStaking));
    }

    ////////////////////////////////////////////////////////////////

    function setUp() public {
        consensus = deployMultiHashConsensusMock();
        withdrawOracle = deployWithdrawOracleMock(address(consensus));
        reportProcessor1 = new MockMultiReportProcessor(CONSENSUS_VERSION);

        initAndSetOtherContract();

        vm.startPrank(DAO);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        consensus.addReportProcessor(address(withdrawOracle));
        consensus.addReportProcessor(address(reportProcessor1));

        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 3);
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 3);

        withdrawOracle.setLiquidStaking(address(liquidStaking));
        withdrawOracle.setVaultManager(address(vaultManager));
        withdrawOracle.updateContractVersion(WITHDRAW_ORACLE_CONTRACT_VERSION);

        vm.stopPrank();
    }

    function triggerConsensusOnHash() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hash = mockWithdrawOracleReportDataMock1Hash_1(refSlot);

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash);
        (, bytes32[] memory consensusReport) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport, hashArrZero()));

        bool isReportProcessing = consensus.getIsReportProcessing(address(withdrawOracle));
        assertFalse(isReportProcessing);

        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash);

        // committee reaches consensus
        console.log("committee reaches consensus");

        (uint256 refSlot2, bytes32[] memory consensusReport2) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport2, hash));
        assertEq(refSlot2, refSlot);

        bool isReportProcessing2 = consensus.getIsReportProcessing(address(withdrawOracle));
        assertFalse(isReportProcessing2);

        (bytes32 reportHash, uint256 reportRefSlot, uint256 reportProcessingDeadlineTime, bool reportProcessingStarted)
        = withdrawOracle.getConsensusReport();
        assertEq(reportHash, hash[0]);
        assertEq(reportRefSlot, refSlot);
        assertEq(reportProcessingDeadlineTime, computeTimestampAtSlot(refSlot + SLOTS_PER_FRAME));
        assertFalse(reportProcessingStarted);

        (uint256 curRefSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        WithdrawOracleWithTimer.ProcessingState memory procState = withdrawOracle.getProcessingState();

        assertEq(procState.currentFrameRefSlot, curRefSlot);
        assertEq(procState.dataHash, reportHash);
        assertEq(procState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertFalse(procState.dataSubmitted);
        assertEq(procState.reportExitedCount, 0);
    }

    // forge test -vvvv --match-test testStructHash
    // result: The array hash is different; The structure is different, the hash is the same
    function testStructHash() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // Two structures hash
        console.log("-------Two different struct hash is same----------");
        assertFalse(mockDifferentStructHashIsSame());
        console.log("-------Two same struct hash is same----------");
        assertTrue(mockSameStructHashIsSame());

        // Two structures array hash
        console.log("-------Two different struct array hash is same----------");
        assertFalse(mockDifferentStructArrayHashIsSame());
        console.log("-------Two same struct array hash is same----------");
        assertTrue(mockSameStructArrayHashIsSame());

        // Two structures array and array + Property hash
        console.log("-------struct hash 1 compare 2----------");
        assertFalse(
            mockWithdrawOracleReportDataMock1Hash_1(refSlot)[0] == mockWithdrawOracleReportDataMock1Hash_2(refSlot)[0]
        );
        console.log("-------struct hash 1 compare 3----------");
        assertFalse(
            mockWithdrawOracleReportDataMock1Hash_1(refSlot)[0] == mockWithdrawOracleReportDataMock1Hash_3(refSlot)[0]
        );
        console.log("-------struct hash 2 compare 3----------");
        assertFalse(
            mockWithdrawOracleReportDataMock1Hash_2(refSlot)[0] == mockWithdrawOracleReportDataMock1Hash_3(refSlot)[0]
        );
    }

    function reportDataConsensusReached(bytes32[] memory hash) public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash);
        (, bytes32[] memory consensusReport) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport, hashArrZero()));

        bool isReportProcessing = consensus.getIsReportProcessing(address(withdrawOracle));
        assertFalse(isReportProcessing);

        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash);

        // committee reaches consensus
        console.log("committee reaches consensus");

        (uint256 refSlot2, bytes32[] memory consensusReport2) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport2, hash));
        assertEq(refSlot2, refSlot);

        bool isReportProcessing2 = consensus.getIsReportProcessing(address(withdrawOracle));
        assertFalse(isReportProcessing2);

        (bytes32 reportHash, uint256 reportRefSlot, uint256 reportProcessingDeadlineTime, bool reportProcessingStarted)
        = withdrawOracle.getConsensusReport();
        assertEq(reportHash, hash[0]);
        assertEq(reportRefSlot, refSlot);
        assertEq(reportProcessingDeadlineTime, computeTimestampAtSlot(refSlot + SLOTS_PER_FRAME));
        assertFalse(reportProcessingStarted);

        (uint256 curRefSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        WithdrawOracleWithTimer.ProcessingState memory procState = withdrawOracle.getProcessingState();

        assertEq(procState.currentFrameRefSlot, curRefSlot);
        assertEq(procState.dataHash, reportHash);
        assertEq(procState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertFalse(procState.dataSubmitted);
        assertEq(procState.reportExitedCount, 0);
    }

    // forge test -vvvv --match-test testWithdrawOracleConfig
    function testWithdrawOracleConfig() public {
        //-------time-------
        uint256 consensusTime1 = consensus.getTime();
        uint256 oracleTime1 = withdrawOracle.getTime();
        assertEq(consensusTime1, oracleTime1);

        consensus.advanceTimeBy(SECONDS_PER_SLOT);
        assertEq(consensus.getTime(), consensusTime1 + SECONDS_PER_SLOT);
        assertEq(consensus.getTime(), withdrawOracle.getTime());

        //---------contract and version-----------
        assertEq(withdrawOracle.getConsensusContract(), address(consensus));
        assertEq(withdrawOracle.getConsensusVersion(), CONSENSUS_VERSION);
        assertEq(withdrawOracle.SECONDS_PER_SLOT(), SECONDS_PER_SLOT);
    }

    // forge test -vvvv --match-test testInitReportDataMock1State
    // initially, consensus report is empty and is not being processed
    function testInitReportDataMock1State() public {
        (bytes32 initHash, uint256 initRefSlot, uint256 initProcessingDeadlineTime, bool initProcessingStarted) =
            withdrawOracle.getConsensusReport();
        assertEq(initHash, ZERO_HASH);
        assertEq(initProcessingDeadlineTime, 0);
        assertEq(initRefSlot, 0);
        assertFalse(initProcessingStarted);

        (uint256 refSlot,) = consensus.getCurrentFrame();
        WithdrawOracleWithTimer.ProcessingState memory procState = withdrawOracle.getProcessingState();

        assertEq(procState.currentFrameRefSlot, refSlot);
        assertEq(procState.dataHash, ZERO_HASH);
        assertEq(procState.processingDeadlineTime, 0);
        assertFalse(procState.dataSubmitted);
        assertEq(procState.reportExitedCount, 0);
    }

    // forge test -vvvv --match-test testTriggerConsensusOnHash
    function testTriggerConsensusOnHash() public {
        // consensus 已达到上报状态
        triggerConsensusOnHash();
    }

    // forge test -vvvv --match-test testReportDataMock1FailForDataNotMatch
    function testReportDataMock1FailForDataNotMatch() public {
        triggerConsensusOnHash();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        console.log("-------mockWithdrawOracleReportDataMock1_2----------");

        vm.prank(MEMBER_1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "UnexpectedDataHash(bytes32,bytes32)",
                mockWithdrawOracleReportDataMock1Hash_1(refSlot)[0],
                mockWithdrawOracleReportDataMock1Hash_2(refSlot)[0]
            )
        );
        withdrawOracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_2(refSlot), CONSENSUS_VERSION, moduleId);

        console.log("-------mockWithdrawOracleReportDataMock1_3----------");
        vm.prank(MEMBER_1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "UnexpectedDataHash(bytes32,bytes32)",
                mockWithdrawOracleReportDataMock1Hash_1(refSlot)[0],
                mockWithdrawOracleReportDataMock1Hash_3(refSlot)[0]
            )
        );
        withdrawOracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_3(refSlot), CONSENSUS_VERSION, moduleId);
    }

    // forge test -vvvv --match-test testReportDataMock1Success
    function testReportDataMock1Success() public {
        // consensus 已达到上报状态
        triggerConsensusOnHash();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_1(refSlot), CONSENSUS_VERSION, moduleId);

        WithdrawOracleWithTimer.ProcessingState memory procState = withdrawOracle.getProcessingState();
        assertTrue(procState.dataSubmitted);
    }

    // forge test -vvvv --match-test testMockWithdrawOracleReportDataMock1Count_ForGas
    // Pressure survey Report for gas
    function testMockWithdrawOracleReportDataMock1Count_ForGas() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // exitCount：200 opsCount：0  gas:9071357
        // exitCount：0 opsCount：200  gas:125373
        // exitCount：0 opsCount：1000  gas:429757
        // exitCount：0 opsCount：10000  gas:5404472
        // exitCount：10 opsCount：10000  gas:5859629
        // exitCount：100 opsCount：10000  gas:9938114
        // exitCount：1000 opsCount：0  gas: 45143795

        // Remove the exitValidator to remove the weight
        /// EnumerableSet.UintSet private exitedTokenIds;
        /// if (!exitedTokenIds.add(_exitTokenIds[i]))
        //     revert ValidatorReportedExited(_exitTokenIds[i]);
        // exitCount：100 opsCount：0  gas:66429
        // exitCount：1000 opsCount：0  gas:196795
        // exitCount：1000 opsCount：1000  gas:196795
        // exitCount：10000 opsCount：0  gas:2196553

        // exitCount：1000 opsCount：1000  gas:484942
        // exitCount：10000 opsCount：1000  gas:1687638

        // EnumerableSet.UintSet => mapping
        // mapping(uint256 => bool) private exitedTokenIdMap;
        //  if (exitedTokenIdMap[i]) {
        //     revert ValidatorReportedExited(_exitTokenIds[i]);
        //  } else {
        //     exitedTokenIdMap[i] = true;
        //  }
        // exitCount：10000 opsCount：10000  gas:233711982
        // exitCount：10000 opsCount：0  gas:226016553
        uint256 exitCount = 10000;
        uint256 opsCount = 1000;

        bytes32[] memory hash = mockWithdrawOracleReportDataMock1_countHash(refSlot, exitCount, opsCount);

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash);
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportDataMock1(
            mockWithdrawOracleReportDataMock1_count(refSlot, exitCount, opsCount), CONSENSUS_VERSION, moduleId
        );
    }

    function mockRegisterValidator_3NFT_1NETH()
        public
        pure
        returns (bytes[] memory, bytes[] memory, bytes32[] memory)
    {
        bytes[] memory pubkeys = new bytes[](4);
        bytes[] memory signatures = new bytes[](4);
        bytes32[] memory depositDataRoots = new bytes32[](4);

        // register 3 Validator for user stake NFT
        // WithdrawalCredentials: USER_1

        bytes memory pubkey =
            bytes(hex"b03dd63cbd0f5f64ecc7326b002a97b1cdd9f12de45976310723a69d4112648347350aaad503797f07a14340a1aa8faa");
        bytes memory sign = bytes(
            hex"8775133c30d529d2d38845bf4701594ced41f641dd91c29a72f649cc2917d96a8adcbf8479d1ab03253545f65e6b168c0e6989ac41c6c18044292fbb5f1bb9168b4c9767df5c6b28c2d72870411700c3cb7ceb590e5a33ab26619198944f4c70"
        );
        bytes32 root = bytes32(hex"18e5418f6fedb34d25a7edda2ffeb71816dd6a63eee6ddb0acbcd126ebb4c20a");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        bytes memory pubkey1 =
            bytes(hex"987ced126c2a2b49a862c3fed933310531568aeeb41b91d8dd571f363cf89783f1abdf4d41748bca9806807770980a12");
        bytes memory sign1 = bytes(
            hex"aecb27c5ec6713351317b34b2ba52cb7ccbe981a82c97d0a9db240f22f303c3145effbe191c5cea733b66d43b9238dbc194876edd6b5487285f5fba03f9ac2d60feaf876dec10f3d20948922a091f4a9de4d528466ade48b8d901f94ebfc0a06"
        );
        pubkeys[1] = pubkey1;
        signatures[1] = sign1;
        depositDataRoots[1] = bytes32(hex"ef0ab5a8340175345d593f6765f5ab3b737232fa453e0a097596ad81f05f0ad0");

        bytes memory pubkey2 =
            bytes(hex"b80c2c5ea557296bfca760969afd2c3a22a8eeb27b651a2e7034a7a37ffdd2dd707275e8cfbeb372778ded3c6764f336");
        bytes memory sign2 = bytes(
            hex"a334d5e3819692ba3a63c66e49d7a187c823449ba195fe2e8a649830707bf998cf2dd563944285d8be601789db2a05f808c8e89a1355ed5fd60f5ee0793397a8d4d367b610433320e63d77a04bbe82bb4cffa7aefc9d73ad68fbb1160c238a6b"
        );
        pubkeys[2] = pubkey2;
        signatures[2] = sign2;
        depositDataRoots[2] = bytes32(hex"c0574294bbcd6bbbd6f927ebddfb4bff37266837dfbc6521c1644926a7126186");

        // register 1 Validator for user stake ETH
        // WithdrawalCredentials: 0x3357c09eCf74C281B6f9CCfAf4D894979349AC4B

        bytes memory pubkey3 =
            bytes(hex"af25ea4b3e76b9ffde2e17ff9f2d6926a36f7e4d297de87e2909d1f1ef234474ed273a092a0d820b777b0296db598912");
        bytes memory sign3 = bytes(
            hex"aaa87a0ad4c91b841fbcf2daec8cca89d0b0ca0dee42ca8809d18ef4e31afc6f69a7686c6a6430a08ff74351521f9b3f07863a9255f1477dc5a849e7b795b7b22b62a478d82d738121b4df14ef33a9494246e8886cd509f1f23f44037b6e68ce"
        );
        bytes32 root3 = bytes32(hex"4f7b8cea459aa8d56527eee847c0633d04e985919ba89f14319e024af49668af");
        pubkeys[3] = pubkey3;
        signatures[3] = sign3;
        depositDataRoots[3] = root3;

        //        bytes memory pubkey4 =
        //            bytes(hex"8ff71f24af862e8627b34cb2ad85c794fac6a73f3ffea4ad59ca96e912800c64c0c9be708d66556434f90e6367a4f42b");
        //        bytes memory sign4 = bytes(
        //            hex"a1f74e42771139b594ffb76b19494340fad978e38d6cf0573e53be86e1b4f204d2b61e7d54b0b78b62f7b8d22c8b2b5306178b73fff7036fc67eec7bb224a057952d4d23cbc414f3acf211655207dfa8e9fe4944944aa6f94097e20b9cd1e852"
        //        );
        //        bytes32 root4 = bytes32(hex"198f5bbf0827aafd3b6f859f2b2a5a3db34370ea9fc6f0874949e287ebb18ce8");
        //        pubkeys[4] = pubkey4;
        //        signatures[4] = sign4;
        //        depositDataRoots[4] = root4;
        //
        //        bytes memory pubkey5 =
        //            bytes(hex"85523875e4ceaf1b275e5274f1ed0f68737c028dd615d96b1af28b20d74a03e883a03ae4148c387e0b164fa3a0778424");
        //        bytes memory sign5 = bytes(
        //            hex"ab926a61d760202555925fe08d0494366dbcd1420136006d8896a4f9780e7d4f595aa3456c8c970b8803b3ae81a2f348063f93c49ebf3492897d6c450ee47f434d54873140aa074c6784195ba9d002c2f7d5e6a49431dc426d0805e52554e58a"
        //        );
        //        bytes32 root5 = bytes32(hex"bbe4b56b3f2c3b4144e8e00d26e8469f1b721dcbeefb70d6f512b659a0e4fc93");
        //        pubkeys[5] = pubkey5;
        //        signatures[5] = sign5;
        //        depositDataRoots[5] = root5;

        return (pubkeys, signatures, depositDataRoots);
    }

    ////////////////////////////////////////////////////////////////
    //------------ ReportData submit test --------------------
    ////////////////////////////////////////////////////////////////

    // 1. Stake 3 NFTs
    // 2. registerValidator for 6
    // 3. request exit
    // 4. transfer to clVault
    // 5. add block number; deal
    // 6. report
    function initReportData_setContract() public {
        // set block number to 10000
        vm.roll(10000);

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"0100000000000000000000003357c09eCf74C281B6f9CCfAf4D894979349AC4B")
        );

        // stake for 4 validator
        vm.deal(USER_1, 200 ether);
        vm.startPrank(USER_1);
        liquidStaking.stakeNFT{value: 96 ether}(1, USER_1);
        liquidStaking.stakeETH{value: 32 ether}(1);
        vm.stopPrank();

        (bytes[] memory pubkeys, bytes[] memory signatures, bytes32[] memory depositDataRoots) =
            mockRegisterValidator_3NFT_1NETH();

        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

        // set block number to 15000
        vm.roll(15000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 2 ether);

        vm.startPrank(USER_1);
        uint256[] memory tokenIds = vnft.activeNftsOfUser();

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            console2.log("user token id:", tokenIds[i]);
        }
        vm.stopPrank();
    }

    //--------------------------stake 3 Nft To 2 Operator--------------------------------------
    function stake3NftTo2Operator() public {
        operatorRegistry.registerOperator{value: 1.1 ether}(
            "two", _controllerAddress2, address(4), _rewardAddresses, _ratios
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(2);

        bytes[] memory pubkeys = new bytes[](2);
        bytes[] memory signatures = new bytes[](2);
        bytes32[] memory depositDataRoots = new bytes32[](2);

        bytes memory pubkey =
            bytes(hex"b03dd63cbd0f5f64ecc7326b002a97b1cdd9f12de45976310723a69d4112648347350aaad503797f07a14340a1aa8faa");
        bytes memory sign = bytes(
            hex"8775133c30d529d2d38845bf4701594ced41f641dd91c29a72f649cc2917d96a8adcbf8479d1ab03253545f65e6b168c0e6989ac41c6c18044292fbb5f1bb9168b4c9767df5c6b28c2d72870411700c3cb7ceb590e5a33ab26619198944f4c70"
        );
        bytes32 root = bytes32(hex"18e5418f6fedb34d25a7edda2ffeb71816dd6a63eee6ddb0acbcd126ebb4c20a");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        bytes memory pubkey1 =
            bytes(hex"987ced126c2a2b49a862c3fed933310531568aeeb41b91d8dd571f363cf89783f1abdf4d41748bca9806807770980a12");
        bytes memory sign1 = bytes(
            hex"aecb27c5ec6713351317b34b2ba52cb7ccbe981a82c97d0a9db240f22f303c3145effbe191c5cea733b66d43b9238dbc194876edd6b5487285f5fba03f9ac2d60feaf876dec10f3d20948922a091f4a9de4d528466ade48b8d901f94ebfc0a06"
        );
        pubkeys[1] = pubkey1;
        signatures[1] = sign1;
        depositDataRoots[1] = bytes32(hex"ef0ab5a8340175345d593f6765f5ab3b737232fa453e0a097596ad81f05f0ad0");

        bytes[] memory pubkeys2 = new bytes[](1);
        bytes[] memory signatures2 = new bytes[](1);
        bytes32[] memory depositDataRoots2 = new bytes32[](1);

        bytes memory pubkey2 =
            bytes(hex"b80c2c5ea557296bfca760969afd2c3a22a8eeb27b651a2e7034a7a37ffdd2dd707275e8cfbeb372778ded3c6764f336");
        bytes memory sign2 = bytes(
            hex"a334d5e3819692ba3a63c66e49d7a187c823449ba195fe2e8a649830707bf998cf2dd563944285d8be601789db2a05f808c8e89a1355ed5fd60f5ee0793397a8d4d367b610433320e63d77a04bbe82bb4cffa7aefc9d73ad68fbb1160c238a6b"
        );

        pubkeys2[0] = pubkey2;
        signatures2[0] = sign2;
        depositDataRoots2[0] = bytes32(hex"c0574294bbcd6bbbd6f927ebddfb4bff37266837dfbc6521c1644926a7126186");

        // set block number to 10000
        vm.roll(10000);

        // stake for 4 validator
        vm.deal(USER_1, 200 ether);
        vm.startPrank(USER_1);
        liquidStaking.stakeNFT{value: 64 ether}(1, USER_1);
        liquidStaking.stakeNFT{value: 32 ether}(2, USER_1);

        vm.stopPrank();

        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
        vm.prank(address(_controllerAddress2));
        liquidStaking.registerValidator(pubkeys2, signatures2, depositDataRoots2);

        vm.startPrank(USER_1);
        uint256[] memory tokenIds = vnft.activeNftsOfUser();

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            console2.log("user token id:", tokenIds[i]);
        }
        vm.stopPrank();
    }

    // test for not exit for report
    // forge test -vvvv --match-test testReportData_notExit
    function testReportData_notExit() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hash = mockFinalReportDataHash_1(refSlot);
        reportDataConsensusReached(hash);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockFinalReportData_1(refSlot), CONSENSUS_VERSION, moduleId);
    }

    // forge test -vvvv --match-test testCheckTotalClBalance
    function testCheckTotalClBalance() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        uint256 preTotal =
            withdrawOracle.clVaultBalance() + withdrawOracle.clBalances() - withdrawOracle.lastClSettleAmount();
        uint256 maxTotal = preTotal + withdrawOracle.pendingBalances()
            + preTotal * (refSlot - 0) * 10 / 100 / 365 / 7200 + withdrawOracle.totalBalanceTolerate();

        assertEq(maxTotal, 0);
    }

    //---------------------------- vNFT token 0 1 2 ------------------------------------
    //---------------------------- nETH token 3 4 5 ------------------------------------

    //----------------------------- ReportData for 3 NFT exit  -----------------------------------
    // forge test -vvvv --match-test testReportData_3validatorExit
    function testReportData_3validatorExit() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        initReportData_setContract();

        // unstake
        // set block number to 20000
        vm.roll(20000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 2 ether);

        vm.startPrank(USER_1);
        // VNFT unstake
        uint256[] memory needUnstakeTokenIds = new uint256[](3);
        needUnstakeTokenIds[0] = 0;
        needUnstakeTokenIds[1] = 1;
        needUnstakeTokenIds[2] = 2;
        withdrawalRequest.unstakeNFT(needUnstakeTokenIds);
        vm.stopPrank();

        bytes32[] memory hash = mockFinalReportData_3validatorExit_hash(refSlot);
        reportDataConsensusReached(hash);

        // transfer to clVault
        vm.deal(address(consensusVaultContract), 98 ether);

        vm.roll(20200);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockFinalReportData_3validatorExit(refSlot), CONSENSUS_VERSION, moduleId);
    }

    //    ----------------------------- ReportData for 3 NFT exit and 1 delayed  -----------------------------------
    //     forge test -vvvv --match-test testReportData_3validatorExit_1delayed
    function testReportData_3validatorExit_1delayed() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // operatorSlash.delayedExitSlashStandard() = 7200

        initReportData_setContract();

        // unstake
        // set block number to 20000
        vm.roll(20000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 2 ether);

        vm.startPrank(USER_1);
        // VNFT unstake
        uint256[] memory needUnstakeTokenIds = new uint256[](3);
        needUnstakeTokenIds[0] = 0;
        needUnstakeTokenIds[1] = 1;
        needUnstakeTokenIds[2] = 2;
        withdrawalRequest.unstakeNFT(needUnstakeTokenIds);
        vm.stopPrank();

        bytes32[] memory hash = mockFinalReportData_3validatorExit_1delayed_hash(refSlot);
        reportDataConsensusReached(hash);

        vm.roll(30200);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(
            mockFinalReportData_3validatorExit_1delayed(refSlot), CONSENSUS_VERSION, moduleId
        );
    }

    // ----------------------------- ReportData for 3 NFT exit; 1 largeExitRequest while delayed  -----------------------------------
    // forge test -vvvv --match-test testReportData_3validatorExit_1delayed_1largeExitRequest_1delayed
    function testReportData_3validatorExit_1delayed_1largeExitRequest_1delayed() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // operatorSlash.delayedExitSlashStandard() = 7200

        initReportData_setContract();

        // unstake
        // set block number to 20000
        vm.roll(20000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 2 ether);

        vm.startPrank(USER_1);
        // VNFT unstake
        uint256[] memory needUnstakeTokenIds = new uint256[](3);
        needUnstakeTokenIds[0] = 0;
        needUnstakeTokenIds[1] = 1;
        needUnstakeTokenIds[2] = 2;
        withdrawalRequest.unstakeNFT(needUnstakeTokenIds);

        // nETH requestLargeWithdrawals
        uint256[] memory _amount = new uint256[](1);
        _amount[0] = 32 ether;
        withdrawalRequest.requestLargeWithdrawals(1, _amount);
        vm.stopPrank();

        // set consensusVault exit's amount
        vm.deal(address(consensusVaultContract), 500 ether);

        bytes32[] memory hash = mockFinalReportData_3validatorExit_1delayed_1largeExitRequest_1delayed_hash(refSlot);
        reportDataConsensusReached(hash);

        vm.roll(30200);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(
            mockFinalReportData_3validatorExit_1delayed_1largeExitRequest_1delayed(refSlot), CONSENSUS_VERSION, moduleId
        );
    }

    // ----------------------------- ReportData for OperatorReward  -----------------------------------
    // forge test -vvvv --match-test testReportData_OperatorReward
    function testReportData_OperatorReward() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        stake3NftTo2Operator();

        // set block number to 15000
        vm.roll(15000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 11 ether);

        bytes32[] memory hash = mockFinalReportData_OperatorReward_hash(refSlot);
        reportDataConsensusReached(hash);

        vm.roll(20000);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockFinalReportData_OperatorReward(refSlot), CONSENSUS_VERSION, moduleId);
    }

    ////////////////////////////////////////////////////////////////
    //------------ Batch ReportData submit test and Gas test -------
    ////////////////////////////////////////////////////////////////

    function toBytes(uint256 x) public returns (bytes memory b) {
        b = new bytes(32);
        assembly {
            mstore(add(b, 32), x)
        }
    }

    //--------------------------stake 100 Nft To 100 Operator per 1--------------------------------------
    function stake100NftTo100Operator() public {
        // set block number to 10000
        vm.roll(10000);

        // stake for 4 validator
        vm.deal(USER_1, 20000 ether);

        for (uint256 i = 2; i < 102; ++i) {
            address controller = address(uint160(i));

            operatorRegistry.registerOperator{value: 1.1 ether}(
                "batch100", controller, address(4), _rewardAddresses, _ratios
            );
            vm.prank(_dao);
            operatorRegistry.setTrustedOperator(i);

            bytes[] memory pubkeys = new bytes[](1);
            bytes[] memory signatures = new bytes[](1);
            bytes32[] memory depositDataRoots = new bytes32[](1);

            bytes memory pubkey = toBytes(i);
            bytes memory sign = bytes(
                hex"8775133c30d529d2d38845bf4701594ced41f641dd91c29a72f649cc2917d96a8adcbf8479d1ab03253545f65e6b168c0e6989ac41c6c18044292fbb5f1bb9168b4c9767df5c6b28c2d72870411700c3cb7ceb590e5a33ab26619198944f4c70"
            );
            bytes32 root = bytes32(hex"18e5418f6fedb34d25a7edda2ffeb71816dd6a63eee6ddb0acbcd126ebb4c20a");
            pubkeys[0] = pubkey;
            signatures[0] = sign;
            depositDataRoots[0] = root;

            vm.prank(USER_1);
            liquidStaking.stakeNFT{value: 32 ether}(i, USER_1);

            vm.prank(controller);
            liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
        }
    }

    //--------------------------stake 100 Nft To 50 Operator per 2--------------------------------------
    function stake100NftTo50Operator() public {
        // set block number to 10000
        vm.roll(10000);

        // stake for 4 validator
        vm.deal(USER_1, 20000 ether);

        for (uint256 i = 2; i < 52; ++i) {
            address controller = address(uint160(i));

            operatorRegistry.registerOperator{value: 1.1 ether}(
                "batch50", controller, address(4), _rewardAddresses, _ratios
            );
            vm.prank(_dao);
            operatorRegistry.setTrustedOperator(i);

            bytes[] memory pubkeys = new bytes[](2);
            bytes[] memory signatures = new bytes[](2);
            bytes32[] memory depositDataRoots = new bytes32[](2);

            bytes memory pubkey = toBytes(i);
            bytes memory sign = bytes(
                hex"8775133c30d529d2d38845bf4701594ced41f641dd91c29a72f649cc2917d96a8adcbf8479d1ab03253545f65e6b168c0e6989ac41c6c18044292fbb5f1bb9168b4c9767df5c6b28c2d72870411700c3cb7ceb590e5a33ab26619198944f4c70"
            );
            bytes32 root = bytes32(hex"18e5418f6fedb34d25a7edda2ffeb71816dd6a63eee6ddb0acbcd126ebb4c20a");
            pubkeys[0] = pubkey;
            signatures[0] = sign;
            depositDataRoots[0] = root;

            bytes memory pubkey2 = toBytes(i + 100);
            pubkeys[1] = pubkey2;
            signatures[1] = sign;
            depositDataRoots[1] = root;

            vm.prank(USER_1);
            liquidStaking.stakeNFT{value: 64 ether}(i, USER_1);

            vm.prank(controller);
            liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
        }
    }

    function stake20NftTo20Operator() public {
        // set block number to 10000
        vm.roll(10000);

        // stake for 4 validator
        vm.deal(USER_1, 20000 ether);

        for (uint256 i = 2; i < 22; ++i) {
            address controller = address(uint160(i));

            operatorRegistry.registerOperator{value: 1.1 ether}(
                "batch100", controller, address(4), _rewardAddresses, _ratios
            );
            vm.prank(_dao);
            operatorRegistry.setTrustedOperator(i);

            bytes[] memory pubkeys = new bytes[](1);
            bytes[] memory signatures = new bytes[](1);
            bytes32[] memory depositDataRoots = new bytes32[](1);

            bytes memory pubkey = toBytes(i);
            bytes memory sign = bytes(
                hex"8775133c30d529d2d38845bf4701594ced41f641dd91c29a72f649cc2917d96a8adcbf8479d1ab03253545f65e6b168c0e6989ac41c6c18044292fbb5f1bb9168b4c9767df5c6b28c2d72870411700c3cb7ceb590e5a33ab26619198944f4c70"
            );
            bytes32 root = bytes32(hex"18e5418f6fedb34d25a7edda2ffeb71816dd6a63eee6ddb0acbcd126ebb4c20a");
            pubkeys[0] = pubkey;
            signatures[0] = sign;
            depositDataRoots[0] = root;

            vm.prank(USER_1);
            liquidStaking.stakeNFT{value: 32 ether}(i, USER_1);

            vm.prank(controller);
            liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
        }
    }

    ////////////////////////////////////////////////////////////////
    // case:
    // 1. 100 operator reward for 20 ether
    // 2. 100 validator exit
    // 3. 50 validator delayed exit
    ////////////////////////////////////////////////////////////////
    // step:
    // 1. register 100 Operator and set Trusted
    // 2. user stakeNFT 100 to 100 Operator
    // 3. register 100 pubkey for 100 Operator
    // 4. add block number;
    // 4.1 add clVault reward for 20 ether
    // 4.2 unstakeNFT
    // 5. ConsensusReached
    // 6. Report
    ////////////////////////////////////////////////////////////////
    // see gas: 13246237
    // forge test -vvvv --match-test testReportData_nft_batch100
    function testReportData_nft_batch100() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // set block number to 15000
        vm.roll(15000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 20 ether);

        stake100NftTo100Operator();

        vm.startPrank(USER_1);
        // VNFT unstake
        uint256[] memory needUnstakeTokenIds = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            needUnstakeTokenIds[i] = i;
        }
        withdrawalRequest.unstakeNFT(needUnstakeTokenIds);
        vm.stopPrank();

        // set clVault reward
        vm.deal(address(consensusVaultContract), 20 ether);

        bytes32[] memory hash = mockFinalReportData_batch100_hash(refSlot);
        reportDataConsensusReached(hash);

        vm.roll(30000);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockFinalReportData_batch100(refSlot), CONSENSUS_VERSION, moduleId);
    }

    ////////////////////////////////////////////////////////////////
    // case:
    // 1. 50 operator reward for 20 ether
    // 2. 100 validator exit for 50 operator per 2
    ////////////////////////////////////////////////////////////////
    // see gas: 6447008
    // reportConsensusData: 6177961
    // forge test -vvvv --match-test testReportData_nft_batch_normal
    function testReportData_nft_batch_normal() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // set block number to 15000
        vm.roll(15000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 20 ether);

        stake100NftTo50Operator();

        vm.startPrank(USER_1);
        // VNFT unstake
        uint256[] memory needUnstakeTokenIds = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            needUnstakeTokenIds[i] = i;
        }
        withdrawalRequest.unstakeNFT(needUnstakeTokenIds);
        vm.stopPrank();

        // set clVault reward
        vm.deal(address(consensusVaultContract), 20 ether);

        bytes32[] memory hash = mockFinalReportData_batch100_normal_hash(refSlot);
        reportDataConsensusReached(hash);

        vm.roll(30000);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockFinalReportData_batch100_normal(refSlot), CONSENSUS_VERSION, moduleId);
    }

    // see gas: 1875255
    // forge test -vvvv --match-test testReportData_20Nft_20Operator
    function testReportData_20Nft_20Operator() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // set block number to 15000
        vm.roll(15000);
        // set clVault reward
        vm.deal(address(consensusVaultContract), 20 ether);

        stake20NftTo20Operator();

        vm.startPrank(USER_1);
        // VNFT unstake
        uint256[] memory needUnstakeTokenIds = new uint256[](20);
        for (uint256 i = 0; i < 20; ++i) {
            needUnstakeTokenIds[i] = i;
        }
        withdrawalRequest.unstakeNFT(needUnstakeTokenIds);
        vm.stopPrank();

        // set clVault reward
        vm.deal(address(consensusVaultContract), 20 ether);

        bytes32[] memory hash = mockFinalReportData_20Nft_20Operator_hash(refSlot);
        reportDataConsensusReached(hash);

        vm.roll(30000);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockFinalReportData_20Nft_20Operator(refSlot), CONSENSUS_VERSION, moduleId);
    }

    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////
    //------------ ReportData settle test --------------------
    ////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////
    // ReportData for 3 NFT exit; 1 largeExitRequest while delayed
    // testReportData_3validatorExit_1delayed_1largeExitRequest_1delayed()
    ///
    // case:
    // 1. operator pledgeBalance
    // 2.
    ////////////////////////////////////////////////////////////////
    // forge test -vvvv --match-test testReportData_Settle_3validatorExit_1delayed_1largeExitRequest_1delayed
    function testReportData_Settle_3validatorExit_1delayed_1largeExitRequest_1delayed() public {
        (uint256 pledgeBalance,) = operatorRegistry.getPledgeInfoOfOperator(1);

        // report and settle
        testReportData_3validatorExit_1delayed_1largeExitRequest_1delayed();

        uint256 slashPerBlock = operatorSlash.slashAmountPerBlockPerValidator();
        // delayedExitSlashStandard = 7200    res = 800 + 900
        uint256 slashBlock = 28000 + 28100 - (20000 + operatorSlash.delayedExitSlashStandard()) * 2;
        uint256 pledgeBalanceReduce = slashPerBlock * slashBlock;

        // test settle data
        (uint256 pledgeBalanceReport,) = operatorRegistry.getPledgeInfoOfOperator(1);
        //        assertEq(pledgeBalanceReport, pledgeBalance - pledgeBalanceReduce);
    }
}
