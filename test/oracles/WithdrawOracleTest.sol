// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockOracleProvider.sol";
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

// forge test --match-path  test/oracles/WithdrawOracleTest.sol
contract WithdrawOracleTest is Test, MockOracleProvider {
    HashConsensusWithTimer consensus;
    WithdrawOracleWithTimer withdrawOracle;

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

    address _dao = DAO;
    address _daoValutAddress = address(2);
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
    address[] _rewardAddresses = new address[] (1);
    uint256[] _ratios = new uint256[] (1);

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
        operatorRegistry.setLiquidStaking(address(liquidStaking));
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
            _dao,
            address(liquidStaking),
            address(vnft),
            address(neth),
            address(operatorRegistry),
            address(withdrawalRequest),
            address(vaultManager)
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
        operatorRegistry.setOperatorSlashContract(address(operatorSlash));
        vm.prank(_dao);
        liquidStaking.initializeV2(
            _operatorIds,
            _users,
            _nethAmounts,
            address(consensusVaultContract),
            address(vaultManager),
            address(withdrawalRequest),
            address(operatorSlash)
        );

        vaultManager.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawOracle),
            address(operatorSlash)
        );
    }

    ////////////////////////////////////////////////////////////////

    function setUp() public {
        (consensus, withdrawOracle) = deployWithdrawOracleMock();

        initAndSetOtherContract();

        vm.startPrank(DAO);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 3);
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 3);

        withdrawOracle.setLiquidStaking(address(liquidStaking));
        withdrawOracle.setVaultManager(address(vaultManager));

        vm.stopPrank();
    }

    function triggerConsensusOnHash() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32 hash = mockWithdrawOracleReportDataMock1Hash_1(refSlot);

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        (, bytes32 consensusReport, bool isReportProcessing) = consensus.getConsensusState();
        assertEq(consensusReport, ZERO_HASH);
        assertFalse(isReportProcessing);

        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);

        // committee reaches consensus
        console.log("committee reaches consensus");

        (uint256 refSlot2, bytes32 consensusReport2, bool isReportProcessing2) = consensus.getConsensusState();
        assertEq(consensusReport2, hash);
        assertEq(refSlot2, refSlot);
        assertFalse(isReportProcessing2);

        (bytes32 reportHash, uint256 reportRefSlot, uint256 reportProcessingDeadlineTime, bool reportProcessingStarted)
        = withdrawOracle.getConsensusReport();
        assertEq(reportHash, hash);
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
            mockWithdrawOracleReportDataMock1Hash_1(refSlot) == mockWithdrawOracleReportDataMock1Hash_2(refSlot)
        );
        console.log("-------struct hash 1 compare 3----------");
        assertFalse(
            mockWithdrawOracleReportDataMock1Hash_1(refSlot) == mockWithdrawOracleReportDataMock1Hash_3(refSlot)
        );
        console.log("-------struct hash 2 compare 3----------");
        assertFalse(
            mockWithdrawOracleReportDataMock1Hash_2(refSlot) == mockWithdrawOracleReportDataMock1Hash_3(refSlot)
        );
    }

    function reportDataConsensusReached() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32 hash = mockFinalReportDataHash_1(refSlot);

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        (, bytes32 consensusReport, bool isReportProcessing) = consensus.getConsensusState();
        assertEq(consensusReport, ZERO_HASH);
        assertFalse(isReportProcessing);

        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);

        // committee reaches consensus
        console.log("committee reaches consensus");

        (uint256 refSlot2, bytes32 consensusReport2, bool isReportProcessing2) = consensus.getConsensusState();
        assertEq(consensusReport2, hash);
        assertEq(refSlot2, refSlot);
        assertFalse(isReportProcessing2);

        (bytes32 reportHash, uint256 reportRefSlot, uint256 reportProcessingDeadlineTime, bool reportProcessingStarted)
        = withdrawOracle.getConsensusReport();
        assertEq(reportHash, hash);
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
                mockWithdrawOracleReportDataMock1Hash_1(refSlot),
                mockWithdrawOracleReportDataMock1Hash_2(refSlot)
            )
        );
        withdrawOracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_2(refSlot), CONSENSUS_VERSION);

        console.log("-------mockWithdrawOracleReportDataMock1_3----------");
        vm.prank(MEMBER_1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "UnexpectedDataHash(bytes32,bytes32)",
                mockWithdrawOracleReportDataMock1Hash_1(refSlot),
                mockWithdrawOracleReportDataMock1Hash_3(refSlot)
            )
        );
        withdrawOracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_3(refSlot), CONSENSUS_VERSION);
    }

    // forge test -vvvv --match-test testReportDataMock1Success
    function testReportDataMock1Success() public {
        // consensus 已达到上报状态
        triggerConsensusOnHash();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_1(refSlot), CONSENSUS_VERSION);

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

        bytes32 hash = mockWithdrawOracleReportDataMock1_countHash(refSlot, exitCount, opsCount);

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportDataMock1(
            mockWithdrawOracleReportDataMock1_count(refSlot, exitCount, opsCount), CONSENSUS_VERSION
        );
    }

    // -------------------------------ReportData submit---------------------------------

    // forge test -vvvv --match-test testReportDataMock_1
    function testReportDataMock_1() public {
        reportDataConsensusReached();
        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockFinalReportData_1(refSlot), CONSENSUS_VERSION);
    }
}
