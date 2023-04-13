// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockOracleProvider.sol";
import "test/helpers/oracles/WithdrawOracleWithTimer.sol";

// forge test --match-path  test/oracles/WithdrawOracleTest.sol
contract WithdrawOracleTest is Test, MockOracleProvider {
    HashConsensusWithTimer consensus;
    WithdrawOracleWithTimer oracle;

    function setUp() public {
        (consensus, oracle) = deployWithdrawOracleMock();

        vm.startPrank(DAO);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 3);
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 3);
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
        = oracle.getConsensusReport();
        assertEq(reportHash, hash);
        assertEq(reportRefSlot, refSlot);
        assertEq(reportProcessingDeadlineTime, computeTimestampAtSlot(refSlot + SLOTS_PER_FRAME));
        assertFalse(reportProcessingStarted);

        (uint256 curRefSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        WithdrawOracleWithTimer.ProcessingState memory procState = oracle.getProcessingState();

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

    // forge test -vvvv --match-test testWithdrawOracleConfig
    function testWithdrawOracleConfig() public {
        //-------time-------
        uint256 consensusTime1 = consensus.getTime();
        uint256 oracleTime1 = oracle.getTime();
        assertEq(consensusTime1, oracleTime1);

        consensus.advanceTimeBy(SECONDS_PER_SLOT);
        assertEq(consensus.getTime(), consensusTime1 + SECONDS_PER_SLOT);
        assertEq(consensus.getTime(), oracle.getTime());

        //---------contract and version-----------
        assertEq(oracle.getConsensusContract(), address(consensus));
        assertEq(oracle.getConsensusVersion(), CONSENSUS_VERSION);
        assertEq(oracle.SECONDS_PER_SLOT(), SECONDS_PER_SLOT);
    }

    // forge test -vvvv --match-test testInitReportDataMock1State
    // initially, consensus report is empty and is not being processed
    function testInitReportDataMock1State() public {
        (bytes32 initHash, uint256 initRefSlot, uint256 initProcessingDeadlineTime, bool initProcessingStarted) =
            oracle.getConsensusReport();
        assertEq(initHash, ZERO_HASH);
        assertEq(initProcessingDeadlineTime, 0);
        assertEq(initRefSlot, 0);
        assertFalse(initProcessingStarted);

        (uint256 refSlot,) = consensus.getCurrentFrame();
        WithdrawOracleWithTimer.ProcessingState memory procState = oracle.getProcessingState();

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
        oracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_2(refSlot), CONSENSUS_VERSION);

        console.log("-------mockWithdrawOracleReportDataMock1_3----------");
        vm.prank(MEMBER_1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "UnexpectedDataHash(bytes32,bytes32)",
                mockWithdrawOracleReportDataMock1Hash_1(refSlot),
                mockWithdrawOracleReportDataMock1Hash_3(refSlot)
            )
        );
        oracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_3(refSlot), CONSENSUS_VERSION);
    }

    // forge test -vvvv --match-test testReportDataMock1Success
    function testReportDataMock1Success() public {
        // consensus 已达到上报状态
        triggerConsensusOnHash();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        oracle.submitReportDataMock1(mockWithdrawOracleReportDataMock1_1(refSlot), CONSENSUS_VERSION);

        WithdrawOracleWithTimer.ProcessingState memory procState = oracle.getProcessingState();
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
        oracle.submitReportDataMock1(
            mockWithdrawOracleReportDataMock1_count(refSlot, exitCount, opsCount), CONSENSUS_VERSION
        );
    }
}
