// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockHashConsensusWithTimerProvider.sol";
import "test/helpers/oracles/MockReportProcessor.sol";

// forge test --match-path  test/oracles/HashConsensusTest.sol
contract HashConsensusTest is Test, MockHashConsensusWithTimerProvider {
    HashConsensusWithTimer consensus;
    MockReportProcessor reportProcessor;

    function setUp() public {
        (consensus, reportProcessor) = deployHashConsensusMock();

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
    }
}
