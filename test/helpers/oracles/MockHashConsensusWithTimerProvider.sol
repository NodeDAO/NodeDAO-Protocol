// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockReportProcessor.sol";
import "test/helpers/CommonConstantProvider.sol";

// Provide baseline data for the Hash Consensus contract test
contract MockHashConsensusWithTimerProvider is CommonConstantProvider {
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    uint256 public constant GENESIS_TIME = 100;
    uint256 public constant EPOCHS_PER_FRAME = 225;
    uint256 public constant INITIAL_EPOCH = 1;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 1;

    address public constant MEMBER_1 = address(11);
    address public constant MEMBER_2 = address(12);
    address public constant MEMBER_3 = address(13);
    address public constant MEMBER_4 = address(14);
    address public constant MEMBER_5 = address(15);

    function computeTimestampAtEpoch(uint256 _epoch) public pure returns (uint256) {
        return GENESIS_TIME + _epoch * SECONDS_PER_EPOCH;
    }

    function computeTimestampAtSlot(uint256 _slot) public pure returns (uint256) {
        return GENESIS_TIME + _slot * SECONDS_PER_SLOT;
    }

    function computeEpochFirstSlot(uint256 _epoch) public pure returns (uint256) {
        return _epoch * SLOTS_PER_EPOCH;
    }

    function computeEpochFirstSlotAt(uint256 _time) public pure returns (uint256) {
        return computeEpochFirstSlot(computeEpochAt(_time));
    }

    function computeSlotAt(uint256 _time) public pure returns (uint256) {
        return (_time - GENESIS_TIME) / SECONDS_PER_SLOT;
    }

    function computeEpochAt(uint256 _time) public pure returns (uint256) {
        return computeSlotAt(_time) / SLOTS_PER_EPOCH;
    }

    function deployHashConsensusMock() public returns (HashConsensusWithTimer, MockReportProcessor) {
        MockReportProcessor reportProcessor = new MockReportProcessor(CONSENSUS_VERSION);
        HashConsensusWithTimer consensus = new HashConsensusWithTimer();
        consensus.initialize(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            EPOCHS_PER_FRAME,
            INITIAL_FAST_LANE_LENGTH_SLOTS,
            DAO,
            address(reportProcessor)
        );

        return (consensus, reportProcessor);
    }

    function setTimeToFrame0(HashConsensusWithTimer consensus) public {
        consensus.setTimeInEpochs(INITIAL_EPOCH);
    }

    function getFastLaneLengthSlotsLimit(HashConsensusWithTimer consensus)
        public
        view
        returns (uint256 fastLaneLengthSlotsLimit)
    {
        (, uint256 epochsPerFrame,) = consensus.getFrameConfig();
        (uint256 slotsPerEpoch,,) = consensus.getChainConfig();
        fastLaneLengthSlotsLimit = slotsPerEpoch * epochsPerFrame;
    }
}
