// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockOracleProvider.sol";
import "test/helpers/oracles/MockReportProcessor.sol";

// forge test --match-path  test/oracles/HashConsensusTest.sol
contract HashConsensusTest is Test, MockOracleProvider {
    HashConsensusWithTimer consensus;
    MockReportProcessor reportProcessor;
    MockReportProcessor reportProcessor2;

    function setUp() public {
        (consensus, reportProcessor) = deployHashConsensusMock();
        reportProcessor2 = new MockReportProcessor(CONSENSUS_VERSION);

        vm.startPrank(DAO);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);
        vm.stopPrank();
    }

    // forge test -vvvv --match-test testFastLane
    function testFastLane() public {
        vm.startPrank(DAO);
        consensus.setFastLaneLengthSlots(getFastLaneLengthSlotsLimit(consensus));
        vm.stopPrank();
    }

    /// ---------------------------Test ConsensusMember--------------------------------
    /// forge test --match-test ConsensusMember
    // forge test -vvvv --match-test testConsensusMemberIsEmpty
    function testConsensusMemberIsEmpty() public {
        (address[] memory addresses, uint256[] memory lastReportedRefSlots) = consensus.getMembers();
        assertEq(addresses.length, 0);
        assertEq(lastReportedRefSlots.length, 0);

        assertFalse(consensus.getIsMember(MEMBER_1));

        HashConsensusWithTimer.MemberConsensusState memory member1Info = consensus.getConsensusStateForMember(MEMBER_1);
        assertFalse(member1Info.isMember);
        assertFalse(member1Info.canReport);
        assertEq(member1Info.lastMemberReportRefSlot, 0);
        assertEq(member1Info.currentFrameMemberReport, ZERO_HASH);

        assertEq(consensus.getQuorum(), 0);
    }

    // forge test -vvvv --match-test testAddConsensusMemberForZeroAddress
    function testAddConsensusMemberForZeroAddress() public {
        vm.startPrank(DAO);
        // Revert adding ZERO_ADDRESS
        vm.expectRevert(abi.encodeWithSignature("AddressCannotBeZero()"));
        consensus.addMember(ZERO_ADDRESS, 1);
        vm.stopPrank();
    }

    // forge test -vvvv --match-test testAddConsensusMemberAndConsensusReportForProcessing
    function testAddConsensusMemberAndConsensusReportForProcessing() public {
        vm.startPrank(DAO);
        consensus.addMember(MEMBER_1, 1);

        /// -----------------------add one member to query--------------------------------
        assertTrue(consensus.getIsMember(MEMBER_1));

        (address[] memory addresses, uint256[] memory lastReportedRefSlots) = consensus.getMembers();
        assertEq(addresses.length, 1);
        assertEq(lastReportedRefSlots.length, 1);
        assertEq(addresses[0], MEMBER_1);

        HashConsensusWithTimer.MemberConsensusState memory member1Info = consensus.getConsensusStateForMember(MEMBER_1);
        assertTrue(member1Info.isMember);
        assertTrue(member1Info.canReport);
        assertEq(member1Info.lastMemberReportRefSlot, 0);
        assertEq(member1Info.currentFrameMemberReport, ZERO_HASH);

        assertEq(consensus.getQuorum(), 1);

        /// ------------------------fail to add one case-------------------------------------
        // doesn't allow to add the same member twice
        vm.expectRevert(abi.encodeWithSignature("DuplicateMember()"));
        consensus.addMember(MEMBER_1, 1);

        // requires quorum to be more than half of the total members count
        vm.expectRevert(abi.encodeWithSignature("QuorumTooSmall(uint256,uint256)", 2, 1));
        consensus.addMember(MEMBER_2, 1);

        /// ------------------------add more member case--------------------------------
        // allows setting the quorum more than total members count
        // QuorumSet(newQuorum: 3, totalMembers: 2, prevQuorum: 1)
        // todo quorum > member 为什么会允许这样？ 岂不是永远不会触发？
        consensus.addMember(MEMBER_2, 3);

        // lowering the quorum while adding a member may trigger consensus
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 4);

        vm.stopPrank();

        ///----------------------Report test-----------------------------
        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);

        // test ConsensusState not to quorum
        (, bytes32 notQuorumConsensusReport,) = consensus.getConsensusState();
        assertEq(notQuorumConsensusReport, ZERO_HASH);

        // Add MEMBER_5, set quorum to 3, and observe the reported result
        vm.prank(DAO);
        consensus.addMember(MEMBER_5, 3);

        (, bytes32 quorum3ConsensusReport,) = consensus.getConsensusState();
        assertEq(quorum3ConsensusReport, HASH_1);
    }

    // forge test -vvvv --match-test testReportAfterAddConsensusMember
    // Re-triggering consensus via members and quorum manipulation
    function testReportAfterAddConsensusMember() public {
        vm.startPrank(DAO);
        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 2);
        vm.stopPrank();

        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);

        (, bytes32 reportState1,) = consensus.getConsensusState();
        assertEq(reportState1, HASH_1);

        vm.prank(DAO);
        consensus.addMember(MEMBER_3, 3);
        (, bytes32 reportState2,) = consensus.getConsensusState();
        assertEq(reportState2, ZERO_HASH);

        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);
        (, bytes32 reportState3,) = consensus.getConsensusState();
        assertEq(reportState3, HASH_1);
    }

    ///------------------------------Test Frame----------------------------------

    // forge test -vvvv --match-test testFrameData
    function testFrameData() public {
        vm.prank(DAO);
        consensus.setFrameConfig(100, 50);

        (uint256 initialEpoch, uint256 epochsPerFrame, uint256 fastLaneLengthSlots) = consensus.getFrameConfig();
        assertEq(initialEpoch, INITIAL_EPOCH);
        assertEq(epochsPerFrame, 100);
        assertEq(fastLaneLengthSlots, 50);
    }

    // forge test -vvvv --match-test testSetFirstEpochInNextFrame
    // should set first epoch in next frame
    function testSetFirstEpochInNextFrame() public {
        consensus.setTimeInEpochs(INITIAL_EPOCH + EPOCHS_PER_FRAME);
        vm.prank(DAO);
        consensus.setFrameConfig(100, 50);

        (uint256 initialEpoch1, uint256 epochsPerFrame1, uint256 fastLaneLengthSlots1) = consensus.getFrameConfig();
        assertEq(initialEpoch1, EPOCHS_PER_FRAME + 1);
        assertEq(epochsPerFrame1, 100);
        assertEq(fastLaneLengthSlots1, 50);
    }

    // forge test -vvvv --match-test testUpdateInitialEpoch
    function testUpdateInitialEpoch() public {
        uint256 initEpoch = 3;
        vm.startPrank(DAO);
        consensus.setTime(100);
        consensus.updateInitialEpoch(initEpoch);
        vm.stopPrank();

        (uint256 initialEpoch,,) = consensus.getFrameConfig();
        assertEq(initialEpoch, initEpoch);

        uint256 initialRefSlot = consensus.getInitialRefSlot();
        assertEq(initialRefSlot, initialEpoch * SLOTS_PER_EPOCH - 1);
    }

    // forge test -vvvv --match-test testReportInterval
    function testReportInterval() public {
        vm.prank(DAO);
        consensus.addMember(MEMBER_1, 1);

        assertEq(consensus.getTime(), computeTimestampAtEpoch(INITIAL_EPOCH));

        vm.prank(DAO);
        consensus.setFrameConfig(5, 0);
        (uint256 initialEpoch,,) = consensus.getFrameConfig();
        assertEq(initialEpoch, INITIAL_EPOCH);

        /// epochs  00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20
        /// before    |-------------r|-------------^|--------------|--------------|
        /// after     |--------------|-------------r|^-------------|--------------|
        ///
        /// notice: this timestamp cannot occur in reality since the time has the discreteness
        /// of SECONDS_PER_SLOT after the Merge; however, we're ignoring this to test the math
        consensus.setTime(computeTimestampAtEpoch(11) - 1);

        (uint256 refSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        assertEq(refSlot, computeEpochFirstSlot(6) - 1);
        assertEq(reportProcessingDeadlineSlot, computeEpochFirstSlot(11) - 1);

        consensus.setTime(computeTimestampAtEpoch(11));
        (uint256 refSlot1, uint256 reportProcessingDeadlineSlot1) = consensus.getCurrentFrame();
        assertEq(refSlot1, computeEpochFirstSlot(11) - 1);
        assertEq(reportProcessingDeadlineSlot1, computeEpochFirstSlot(16) - 1);
    }

    // forge test -vvvv --match-test testInOrDecreaseFrameCase
    function testInOrDecreaseFrameCase() public {
        assertEq(consensus.getTime(), computeTimestampAtEpoch(INITIAL_EPOCH));

        vm.prank(DAO);
        consensus.setFrameConfig(5, 0);
        (uint256 initialEpoch,,) = consensus.getFrameConfig();
        assertEq(initialEpoch, INITIAL_EPOCH);

        /// we're at the last slot of the frame 1 spanning epochs 6-10
        ///
        ///        epochs  00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20
        /// frames before    |-------------r|-------------^|--------------|--------------|
        ///  frames after    |-------------r|-------------^------|--------------------|---
        ///                  |
        /// NOT like this    |-------------------r|-------^-------------|-----------------
        consensus.setTime(computeTimestampAtEpoch(11) - SECONDS_PER_SLOT);

        (uint256 refSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        assertEq(refSlot, computeEpochFirstSlot(6) - 1);
        assertEq(reportProcessingDeadlineSlot, computeEpochFirstSlot(11) - 1);

        /// When frame is set from 5 to 7, the starting slot remains the same and the next reported slot changes
        vm.prank(DAO);
        consensus.setFrameConfig(7, 0);
        (uint256 refSlot1, uint256 reportProcessingDeadlineSlot1) = consensus.getCurrentFrame();
        assertEq(refSlot1, computeEpochFirstSlot(6) - 1);
        assertEq(reportProcessingDeadlineSlot1, computeEpochFirstSlot(13) - 1);

        /// ----------------------------Omit the test----------------------------------------
        /// decreasing the frame size cannot decrease the current reference slot
        ///
        // The same goes for reducing the frame, say from 5 to 4
        /// we're in the first half of the frame 1 spanning epochs 6-10
        ///
        ///        epochs  00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20
        /// frames before    |-------------r|---^----------|--------------|--------------|
        ///  frames after    |-------------r|---^-------|-----------|-----------|--------|
        ///                  |
        /// NOT like this    |----------r|------^----|-----------|-----------|-----------|
        ///
        /// assertEq(refSlot1, computeEpochFirstSlot(6) - 1);
        //  assertEq(reportProcessingDeadlineSlot1, computeEpochFirstSlot(10) - 1);
        ///---------------------------------------------------------------------------------
        /// we're at the end of the frame 1 spanning epochs 6-10
        ///
        ///        epochs  00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20
        /// frames before    |-------------r|------------^-|--------------|--------------|
        ///  frames after    |--------------|----------r|^----------|-----------|---------
        ///                  |
        /// NOT like this    |-----------|----------r|---^-------|-----------|-----------|
        ///
        /// assertEq(refSlot1, computeEpochFirstSlot(10) - 1);
        //  assertEq(reportProcessingDeadlineSlot1, computeEpochFirstSlot(14) - 1);
    }

    /// -------------------------------Report Test-------------------------------------------------

    // forge test -vvvv --match-test testReportingChangeFrame
    // reporting frame changes as more time passes
    function testReportingChangeFrame() public {
        (uint256 refSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();

        uint256 time = consensus.getTime();
        uint256 expectedRefSlot = computeEpochFirstSlotAt(time) - 1;
        uint256 expectedDeadlineSlot = expectedRefSlot + EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

        assertEq(refSlot, expectedRefSlot);
        assertEq(reportProcessingDeadlineSlot, expectedDeadlineSlot);

        // Add a frame
        consensus.advanceTimeBy(SECONDS_PER_FRAME);
        (uint256 refSlot1, uint256 reportProcessingDeadlineSlot1) = consensus.getCurrentFrame();
        assertEq(refSlot1, expectedRefSlot + SLOTS_PER_FRAME);
        assertEq(reportProcessingDeadlineSlot1, expectedDeadlineSlot + SLOTS_PER_FRAME);
    }

    // forge test -vvvv --match-test testFirstMemberVoteHash3
    // first member votes for hash 3
    function testFirstMemberVoteHash3() public {
        vm.prank(DAO);
        consensus.addMember(MEMBER_1, 1);

        HashConsensusWithTimer.MemberConsensusState memory result = consensus.getConsensusStateForMember(MEMBER_1);
        assertTrue(result.canReport);

        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, HASH_3, CONSENSUS_VERSION);
    }

    // forge test -vvvv --match-test testReportNotReached
    // consensus is not reached
    function testReportNotReached() public {
        (, bytes32 consensusReport, bool isReportProcessing) = consensus.getConsensusState();
        assertEq(consensusReport, ZERO_HASH);
        assertFalse(isReportProcessing);

        MockReportProcessor.SubmitReportLastCall memory submitReportLastCall =
            reportProcessor.getLastCall_submitReport();
        assertEq(submitReportLastCall.callCount, 0);

        HashConsensusWithTimer.MemberConsensusState memory memberInfo = consensus.getConsensusStateForMember(MEMBER_1);
        assertEq(memberInfo.currentFrameConsensusReport, ZERO_HASH);
    }

    // forge test -vvvv --match-test testReportReached
    // consensus is reached
    function testReportReached() public {
        vm.startPrank(DAO);
        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 2);
        vm.stopPrank();

        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);

        (, bytes32 reportState1,) = consensus.getConsensusState();
        assertEq(reportState1, HASH_1);

        MockReportProcessor.SubmitReportLastCall memory submitReportLastCall =
            reportProcessor.getLastCall_submitReport();
        assertEq(submitReportLastCall.callCount, 1);

        // ------------Second report-----------
        // add a frame for next report
        consensus.advanceTimeBy(SECONDS_PER_FRAME);

        (uint256 refSlot2,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot2, HASH_1, CONSENSUS_VERSION);
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot2, HASH_1, CONSENSUS_VERSION);

        MockReportProcessor.SubmitReportLastCall memory submitReportLastCall2 =
            reportProcessor.getLastCall_submitReport();
        assertEq(submitReportLastCall2.callCount, 2);
    }

    // forge test -vvvv --match-test testConsensusReportAlreadyProcessing
    // reverts with ConsensusReportAlreadyProcessing
    function testConsensusReportAlreadyProcessing() public {
        vm.prank(DAO);
        consensus.addMember(MEMBER_1, 1);

        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);

        reportProcessor.startReportProcessing();

        vm.prank(MEMBER_1);
        vm.expectRevert(abi.encodeWithSignature("ConsensusReportAlreadyProcessing()"));
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);
    }

    // forge test -vvvv --match-test testDuplicateReport
    // reverts with DuplicateReport
    function testDuplicateReport() public {
        vm.prank(DAO);
        consensus.addMember(MEMBER_1, 1);

        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);

        vm.prank(MEMBER_1);
        vm.expectRevert(abi.encodeWithSignature("DuplicateReport()"));
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);
    }

    ///-----------------------Test Two ReportProcessor-----------------------------------------

    // forge test -vvvv --match-test testTwoReportProcessor
    // consensus is reached
    function testTwoReportProcessor() public {
        // test properly set initial report processor
        assertEq(consensus.getReportProcessor(), address(reportProcessor));

        // checks next processor is not the same as previous
        vm.expectRevert(abi.encodeWithSignature("NewProcessorCannotBeTheSame()"));
        consensus.setReportProcessor(address(reportProcessor));

        // test ReportProcessorSet
        consensus.setReportProcessor(address(reportProcessor2));

        //------test callCount ------
        vm.prank(DAO);
        consensus.addMember(MEMBER_1, 1);

        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, HASH_1, CONSENSUS_VERSION);

        // There is no `processor.startReportProcessing()`
        // to simulate situation when processing still in progress

        MockReportProcessor.SubmitReportLastCall memory submitReportLastCall2 =
            reportProcessor2.getLastCall_submitReport();
        assertEq(submitReportLastCall2.callCount, 1);
    }
}