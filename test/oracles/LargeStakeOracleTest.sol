// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "test/helpers/oracles/MultiHashConsensusWithTimer.sol";
import "test/helpers/oracles/MockLargeOracleProvider.sol";
import "src/oracles/WithdrawOracle.sol";
import "src/oracles/LargeStakeOracle.sol";
import "src/largeStaking/LargeStaking.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/OperatorSlash.sol";
import "src/largeStaking/ELRewardFactory.sol";
import "src/LiquidStaking.sol";
import "src/vault/VaultManager.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/vault/ELVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/ConsensusVault.sol";
import "src/WithdrawalRequest.sol";
import "src/largeStaking/ELReward.sol";
import "src/utils/Array.sol";

// forge test --match-path  test/oracles/LargeStakeOracleTest.sol
contract WithdrawOracleTest is Test, MockLargeOracleProvider {
    MultiHashConsensusWithTimer consensus;
    WithdrawOracle withdrawOracle;
    LargeStakeOracle largeStakeOracle;

    uint256 withdrawOracleModuleId = 1;
    uint256 largeStakeOracleModuleId = 2;

    address _owner = address(555);

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
            address(0), address(0), address(liquidStaking), address(0), address(0), address(0), 0, 0, 0
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
            address(0), address(0), address(liquidStaking), address(operatorSlash), address(0), address(0), 0, 0, 0
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
            address(operatorSlash),
            address(largeStakeOracle),
            address(elRewardFactor),
            address(depositContract)
        );
        vm.prank(_dao);
        operatorRegistry.initializeV3(address(largeStaking));

        vm.prank(_dao);
        largeStaking.setLargeStakingSetting(
            address(0), address(0), 300, 0, address(0), address(0), address(0), address(0)
        );
        vm.prank(_dao);
        operatorSlash.initalizeV2(address(largeStaking));
    }

    ////////////////////////////////////////////////////////////////

    function setUp() public {
        consensus = deployMultiHashConsensusMock();
        withdrawOracle = deployWithdrawOracle(address(consensus));
        largeStakeOracle = deployLargeStakeOracle(address(consensus), address(largeStaking));

        initAndSetOtherContract();

        vm.startPrank(DAO);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        consensus.addReportProcessor(address(withdrawOracle));
        consensus.addReportProcessor(address(largeStakeOracle));

        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 3);
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 3);

        withdrawOracle.setLiquidStaking(address(liquidStaking));
        withdrawOracle.setVaultManager(address(vaultManager));
        withdrawOracle.updateContractVersion(WITHDRAW_ORACLE_CONTRACT_VERSION);

        largeStakeOracle.setLargeStakeContract(address(largeStaking));
        largeStaking.setLargeStakingSetting(
            address(0), address(0), 300, 0, address(0), address(largeStakeOracle), address(0), address(0)
        );

        vm.stopPrank();
    }

    /////////////////////////  test 1 consensus 2 oracle report  ///////////////////////////////////////

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
        WithdrawOracle.ProcessingState memory procState = withdrawOracle.getProcessingState();

        assertEq(procState.currentFrameRefSlot, curRefSlot);
        assertEq(procState.dataHash, reportHash);
        assertEq(procState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertFalse(procState.dataSubmitted);
        assertEq(procState.reportExitedCount, 0);

        (
            bytes32 largeStakeOracleReportHash,
            uint256 largeStakeOracleReportRefSlot,
            uint256 largeStakeOracleReportProcessingDeadlineTime,
            bool largeStakeOracleReportProcessingStarted
        ) = largeStakeOracle.getConsensusReport();

        LargeStakeOracle.ProcessingState memory largeStakeOracleProcState = largeStakeOracle.getProcessingState();
        assertEq(largeStakeOracleProcState.currentFrameRefSlot, curRefSlot);
        assertEq(largeStakeOracleProcState.dataHash, largeStakeOracleReportHash);
        assertEq(largeStakeOracleProcState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertFalse(largeStakeOracleProcState.dataSubmitted);
    }

    // forge test -vvvv --match-test testTwoOracleConsensusReached
    function testTwoOracleConsensusReached() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hashArr = mockLargeStakeOracleEmptyReportDataHash(refSlot);
        reportDataConsensusReached(hashArr);
    }

    // forge test -vvvv --match-test testWithdrawOracleReport
    function testWithdrawOracleReport() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hashArr = mockLargeStakeOracleEmptyReportDataHash(refSlot);
        reportDataConsensusReached(hashArr);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(
            mockWithdrawOracleNoExitReportData(refSlot), WITHDRAW_ORACLE_CONTRACT_VERSION, withdrawOracleModuleId
        );

        (uint256 refSlot2, bytes32[] memory consensusReport2) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport2, hashArr));
        assertEq(refSlot2, refSlot);

        bool isReportProcessing2 = consensus.getIsReportProcessing(address(withdrawOracle));
        assertTrue(isReportProcessing2);

        (bytes32 reportHash, uint256 reportRefSlot, uint256 reportProcessingDeadlineTime, bool reportProcessingStarted)
        = withdrawOracle.getConsensusReport();
        assertEq(reportHash, hashArr[0]);
        assertEq(reportRefSlot, refSlot);
        assertEq(reportProcessingDeadlineTime, computeTimestampAtSlot(refSlot + SLOTS_PER_FRAME));
        assertTrue(reportProcessingStarted);

        (uint256 curRefSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        WithdrawOracle.ProcessingState memory procState = withdrawOracle.getProcessingState();

        assertEq(procState.currentFrameRefSlot, curRefSlot);
        assertEq(procState.dataHash, reportHash);
        assertEq(procState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertTrue(procState.dataSubmitted);
    }

    // forge test -vvvv --match-test testLargeStakeOracleReportEmpty
    function testLargeStakeOracleReportEmpty() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hashArr = mockLargeStakeOracleEmptyReportDataHash(refSlot);
        reportDataConsensusReached(hashArr);

        vm.prank(MEMBER_1);
        vm.expectRevert(abi.encodeWithSignature("ReportDataIsEmpty()"));
        largeStakeOracle.submitReportData(
            mockLargeStakeOracleEmptyReportData(refSlot), LARGE_STAKE_ORACLE_CONTRACT_VERSION, largeStakeOracleModuleId
        );
    }

    function largeStakeForTest() public {
        vm.prank(address(4));
        largeStaking.startupSharedRewardPool(1);

        // shared reward 0
        vm.deal(address(1000), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        (uint256 operatorId, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(0);
        console.log("operatorId", operatorId);
        console.log("rewardPoolAddr", rewardPoolAddr);
        console.log("rewards", rewards);

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        bytes memory pubkey =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        vm.prank(_controllerAddress);
        largeStaking.registerValidator(0, pubkeys, signatures, depositDataRoots);
    }

    // forge test -vvvv --match-test testLargeStakeOracleReportData
    function testLargeStakeOracleReportData() public {
        largeStakeForTest();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hashArr = mockLargeStakeOracleReportDataExitAndSlashHash(refSlot);
        reportDataConsensusReached(hashArr);

        vm.prank(MEMBER_1);
        largeStakeOracle.submitReportData(
            mockLargeStakeOracleReportDataExitAndSlash(refSlot),
            LARGE_STAKE_ORACLE_CONTRACT_VERSION,
            largeStakeOracleModuleId
        );

        (uint256 refSlot2, bytes32[] memory consensusReport2) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport2, hashArr));
        assertEq(refSlot2, refSlot);

        bool isReportProcessing2 = consensus.getIsReportProcessing(address(largeStakeOracle));
        assertTrue(isReportProcessing2);

        (
            bytes32 largeStakeOracleReportHash,
            uint256 largeStakeOracleReportRefSlot,
            uint256 largeStakeOracleReportProcessingDeadlineTime,
            bool largeStakeOracleReportProcessingStarted
        ) = largeStakeOracle.getConsensusReport();
        (uint256 curRefSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        LargeStakeOracle.ProcessingState memory largeStakeOracleProcState = largeStakeOracle.getProcessingState();
        assertEq(largeStakeOracleProcState.currentFrameRefSlot, curRefSlot);
        assertEq(largeStakeOracleProcState.dataHash, largeStakeOracleReportHash);
        assertEq(largeStakeOracleProcState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertTrue(largeStakeOracleProcState.dataSubmitted);
    }

    // forge test -vvvv --match-test testLargeStakeOracleReportDataForTwoOracle
    function testLargeStakeOracleReportDataForTwoOracle() public {
        largeStakeForTest();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hashArr = mockLargeStakeOracleReportDataExitAndSlashHash(refSlot);
        reportDataConsensusReached(hashArr);

        // withdrawOracle report
        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(
            mockWithdrawOracleNoExitReportData(refSlot), WITHDRAW_ORACLE_CONTRACT_VERSION, withdrawOracleModuleId
        );

        (uint256 refSlot2, bytes32[] memory consensusReport2) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport2, hashArr));
        assertEq(refSlot2, refSlot);

        bool isReportProcessing2 = consensus.getIsReportProcessing(address(withdrawOracle));
        assertTrue(isReportProcessing2);

        (bytes32 reportHash, uint256 reportRefSlot, uint256 reportProcessingDeadlineTime, bool reportProcessingStarted)
        = withdrawOracle.getConsensusReport();
        assertEq(reportHash, hashArr[0]);
        assertEq(reportRefSlot, refSlot);
        assertEq(reportProcessingDeadlineTime, computeTimestampAtSlot(refSlot + SLOTS_PER_FRAME));
        assertTrue(reportProcessingStarted);

        (uint256 curRefSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        WithdrawOracle.ProcessingState memory procState = withdrawOracle.getProcessingState();

        assertEq(procState.currentFrameRefSlot, curRefSlot);
        assertEq(procState.dataHash, reportHash);
        assertEq(procState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertTrue(procState.dataSubmitted);

        // largeStakeOracle report
        vm.prank(MEMBER_1);
        largeStakeOracle.submitReportData(
            mockLargeStakeOracleReportDataExitAndSlash(refSlot),
            LARGE_STAKE_ORACLE_CONTRACT_VERSION,
            largeStakeOracleModuleId
        );

        (
            bytes32 largeStakeOracleReportHash,
            uint256 largeStakeOracleReportRefSlot,
            uint256 largeStakeOracleReportProcessingDeadlineTime,
            bool largeStakeOracleReportProcessingStarted
        ) = largeStakeOracle.getConsensusReport();
        (uint256 curRefSlot2, uint256 reportProcessingDeadlineSlot2) = consensus.getCurrentFrame();
        LargeStakeOracle.ProcessingState memory largeStakeOracleProcState = largeStakeOracle.getProcessingState();
        assertEq(largeStakeOracleProcState.currentFrameRefSlot, curRefSlot2);
        assertEq(largeStakeOracleProcState.dataHash, largeStakeOracleReportHash);
        assertEq(
            largeStakeOracleProcState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot2)
        );
        assertTrue(largeStakeOracleProcState.dataSubmitted);
    }
}
