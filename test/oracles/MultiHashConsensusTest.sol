// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "src/utils/Array.sol";
import "test/helpers/oracles/MockMultiOracleProvider.sol";

// forge test --match-path  test/oracles/MultiHashConsensusTest.sol
contract MultiHashConsensusTest is Test, MockMultiOracleProvider {
    MultiHashConsensusWithTimer consensus;
    MockMultiReportProcessor reportProcessor1;
    MockMultiReportProcessor reportProcessor2;
    MockMultiReportProcessor reportProcessor3;

    function setUp() public {
        consensus = deployMultiHashConsensusMock();
        reportProcessor1 = new MockMultiReportProcessor(CONSENSUS_VERSION);
        reportProcessor2 = new MockMultiReportProcessor(CONSENSUS_VERSION);
        reportProcessor3 = new MockMultiReportProcessor(CONSENSUS_VERSION);

        vm.startPrank(DAO);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);
        consensus.addReportProcessor(address(reportProcessor1), 1);
        consensus.addReportProcessor(address(reportProcessor2), 1);
        consensus.addReportProcessor(address(reportProcessor3), 1);
        vm.stopPrank();
    }

    // forge test -vvvv --match-test testCompareBytes32Arrays
    function testCompareBytes32Arrays() public {
        bytes32[] memory arr1 = new bytes32[](2);
        arr1[0] = bytes32(uint256(1));
        arr1[1] = bytes32(uint256(2));

        bytes32[] memory arr2 = new bytes32[](2);
        arr2[0] = bytes32(uint256(1));
        arr2[1] = bytes32(uint256(2));

        assertTrue(Array.compareBytes32Arrays(arr1, arr2));

        arr2[0] = bytes32(uint256(2));
        arr2[1] = bytes32(uint256(1));

        assertFalse(Array.compareBytes32Arrays(arr1, arr2));
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

        MultiHashConsensusWithTimer.MemberConsensusState memory member1Info =
            consensus.getConsensusStateForMember(MEMBER_1);
        assertFalse(member1Info.isMember);
        assertFalse(member1Info.canReport);
        assertEq(member1Info.lastMemberReportRefSlot, 0);
        assertEq(member1Info.currentFrameMemberReport.length, 0);

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

        MultiHashConsensusWithTimer.MemberConsensusState memory member1Info =
            consensus.getConsensusStateForMember(MEMBER_1);
        assertTrue(member1Info.isMember);
        assertTrue(member1Info.canReport);
        assertEq(member1Info.lastMemberReportRefSlot, 0);
        assertEq(member1Info.currentFrameMemberReport.length, 0);

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
        consensus.addMember(MEMBER_2, 3);

        // lowering the quorum while adding a member may trigger consensus
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 4);

        vm.stopPrank();

        ///----------------------Report test-----------------------------
        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hashArr1());
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hashArr1());
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hashArr1());

        // test ConsensusState not to quorum
        (, bytes32[] memory notQuorumConsensusReport) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(notQuorumConsensusReport, hashArrZero()));

        // Add MEMBER_5, set quorum to 3, and observe the reported result
        vm.prank(DAO);
        consensus.addMember(MEMBER_5, 3);

        (, bytes32[] memory quorum3ConsensusReport) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(quorum3ConsensusReport, hashArr1()));
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
        consensus.submitReport(refSlot, hashArr1());
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hashArr1());

        (, bytes32[] memory reportState1) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(reportState1, hashArr1()));

        vm.prank(DAO);
        consensus.addMember(MEMBER_3, 3);
        (, bytes32[] memory reportState2) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(reportState2, hashArrZero()));

        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hashArr1());
        (, bytes32[] memory reportState3) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(reportState3, hashArr1()));
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
        consensus.setTime(GENESIS_TIME);
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

    // forge test -vvvv --match-test testFirstMemberVoteHash
    // first member votes for hash
    function testFirstMemberVoteHash() public {
        vm.prank(DAO);
        consensus.addMember(MEMBER_1, 1);

        MultiHashConsensusWithTimer.MemberConsensusState memory result = consensus.getConsensusStateForMember(MEMBER_1);
        assertTrue(result.canReport);

        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hashArr1());
    }

    // forge test -vvvv --match-test testReportNotReached
    // consensus is not reached
    function testReportNotReached() public {
        (, bytes32[] memory consensusReport) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport, hashArrZero()));

        bool isReportProcessing = consensus.getIsReportProcessing(address(reportProcessor1));
        assertFalse(isReportProcessing);

        MockMultiReportProcessor.SubmitReportLastCall memory submitReportLastCall =
            reportProcessor1.getLastCall_submitReport();
        assertEq(submitReportLastCall.callCount, 0);

        MultiHashConsensusWithTimer.MemberConsensusState memory memberInfo =
            consensus.getConsensusStateForMember(MEMBER_1);
        assertTrue(Array.compareBytes32Arrays(memberInfo.currentFrameConsensusReport, hashArrZero()));

        vm.startPrank(DAO);
        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 2);
        vm.stopPrank();

        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hashArr1());
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hashArr2());

        (, bytes32[] memory reportState1) = consensus.getConsensusState();
        assertFalse(Array.compareBytes32Arrays(reportState1, hashArr1()));
        assertFalse(Array.compareBytes32Arrays(reportState1, hashArr2()));
        assertTrue(Array.compareBytes32Arrays(reportState1, hashArrZero()));
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
        consensus.submitReport(refSlot, hashArr1());
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hashArr1());

        (, bytes32[] memory reportState1) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(reportState1, hashArr1()));

        MockMultiReportProcessor.SubmitReportLastCall memory submitReportLastCall =
            reportProcessor1.getLastCall_submitReport();
        assertEq(submitReportLastCall.callCount, 1);
        assertEq(reportProcessor1.getLastCall_submitReport().report, HASH_1);
        assertEq(reportProcessor2.getLastCall_submitReport().report, HASH_2);

        // ------------Second report-----------
        // add a frame for next report
        consensus.advanceTimeBy(SECONDS_PER_FRAME);

        (uint256 refSlot2,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot2, hashArr1());
        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot2, hashArr1());

        MockMultiReportProcessor.SubmitReportLastCall memory submitReportLastCall2 =
            reportProcessor1.getLastCall_submitReport();
        assertEq(submitReportLastCall2.callCount, 2);
    }

    ///-----------------------Test Two ReportProcessor-----------------------------------------

    // forge test -vvvv --match-test testAddReportProcessor
    // consensus is reached
    function testAddReportProcessor() public {
        // test properly set initial report processor
        assertTrue(consensus.getIsReportProcessor(address(reportProcessor1)));
        assertTrue(consensus.getIsReportProcessor(address(reportProcessor2)));

        MultiHashConsensus.ReportProcessor[] memory reportProcessors = consensus.getReportProcessors();
        assertEq(reportProcessors[0].processor, address(reportProcessor1));
        assertEq(reportProcessors[1].processor, address(reportProcessor2));

        assertEq(consensus.getReportModuleId(address(reportProcessor1)), 1);
        assertEq(consensus.getReportModuleId(address(reportProcessor2)), 2);

        // checks next processor is not the same as previous
        vm.prank(DAO);
        vm.expectRevert(abi.encodeWithSignature("DuplicateReportProcessor()"));
        consensus.addReportProcessor(address(reportProcessor1), 1);

        //        vm.prank(DAO);
        MockMultiReportProcessor reportProcessor4 = new MockMultiReportProcessor(CONSENSUS_VERSION);
        vm.prank(DAO);
        consensus.addReportProcessor(address(reportProcessor4), 1);
        assertEq(consensus.getReportProcessors()[3].processor, address(reportProcessor4));

        //------test callCount ------
        vm.prank(DAO);
        consensus.addMember(MEMBER_1, 1);

        (uint256 refSlot,) = consensus.getCurrentFrame();
        vm.prank(MEMBER_1);
        vm.expectRevert(abi.encodeWithSignature("ReportLenNotEqualReportProcessorsLen()"));
        consensus.submitReport(refSlot, hashArr1());
    }
}
