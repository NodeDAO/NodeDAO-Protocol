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

        bytes32 hash = mockWithdrawOracleReportDataHash_1(refSlot);

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
        assertEq(procState.dataFormat, 0);
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
        assertFalse(mockWithdrawOracleReportDataHash_1(refSlot) == mockWithdrawOracleReportDataHash_2(refSlot));
        console.log("-------struct hash 1 compare 3----------");
        assertFalse(mockWithdrawOracleReportDataHash_1(refSlot) == mockWithdrawOracleReportDataHash_3(refSlot));
        console.log("-------struct hash 2 compare 3----------");
        assertFalse(mockWithdrawOracleReportDataHash_2(refSlot) == mockWithdrawOracleReportDataHash_3(refSlot));
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

    // forge test -vvvv --match-test testInitReportDataState
    // initially, consensus report is empty and is not being processed
    function testInitReportDataState() public {
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
        assertEq(procState.dataFormat, 0);
        assertEq(procState.reportExitedCount, 0);
    }

    // forge test -vvvv --match-test testTriggerConsensusOnHash
    function testTriggerConsensusOnHash() public {
        // consensus 已达到上报状态
        triggerConsensusOnHash();
    }

    // forge test -vvvv --match-test testReportDataFailForDataNotMatch
    function testReportDataFailForDataNotMatch() public {
        triggerConsensusOnHash();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        console.log("-------mockWithdrawOracleReportData_2----------");

        vm.prank(MEMBER_1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "UnexpectedDataHash(bytes32,bytes32)",
                mockWithdrawOracleReportDataHash_1(refSlot),
                mockWithdrawOracleReportDataHash_2(refSlot)
            )
        );
        oracle.submitReportData(mockWithdrawOracleReportData_2(refSlot), CONSENSUS_VERSION);

        console.log("-------mockWithdrawOracleReportData_3----------");
        vm.prank(MEMBER_1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "UnexpectedDataHash(bytes32,bytes32)",
                mockWithdrawOracleReportDataHash_1(refSlot),
                mockWithdrawOracleReportDataHash_3(refSlot)
            )
        );
        oracle.submitReportData(mockWithdrawOracleReportData_3(refSlot), CONSENSUS_VERSION);
    }

    // forge test -vvvv --match-test testReportDataSuccess
    function testReportDataSuccess() public {
        // consensus 已达到上报状态
        triggerConsensusOnHash();

        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        oracle.submitReportData(mockWithdrawOracleReportData_1(refSlot), CONSENSUS_VERSION);
    }

    // forge test -vvvv --match-test testMockWithdrawOracleReportDataCount
    // Pressure survey Report for gas
    function testMockWithdrawOracleReportDataCount() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        // 45000 gas:2143760750
        uint256 count = 45000;

        bytes32 hash = mockWithdrawOracleReportData_countHash(refSlot, count);

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);

        vm.prank(MEMBER_1);
        oracle.submitReportData(mockWithdrawOracleReportData_count(refSlot, count), CONSENSUS_VERSION);
    }
}
