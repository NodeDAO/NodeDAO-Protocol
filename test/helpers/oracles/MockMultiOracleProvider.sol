// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "test/helpers/oracles/MultiHashConsensusWithTimer.sol";
import "test/helpers/oracles/MockMultiReportProcessor.sol";
import "test/helpers/CommonConstantProvider.sol";

// Provide baseline data for the Hash Consensus contract test
contract MockMultiOracleProvider is CommonConstantProvider {
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    // goerli: 1616508000
    // mainnet: 1606824023
    uint256 public constant GENESIS_TIME = 1616508000;
    uint256 public constant EPOCHS_PER_FRAME = 20;
    uint256 public constant INITIAL_EPOCH = 1;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 2;

    address public constant MEMBER_1 = address(11);
    address public constant MEMBER_2 = address(12);
    address public constant MEMBER_3 = address(13);
    address public constant MEMBER_4 = address(14);
    address public constant MEMBER_5 = address(15);

    uint256 public constant DATA_FORMAT_LIST = 1;
    uint256 public constant LAST_PROCESSING_REF_SLOT = 1;
    uint256 public constant EXIT_REQUEST_LIMIT = 1000;
    uint256 public constant CL_VAULT_MIN_SETTLE_LIMIT = 1e19;

    uint256 public constant CL_BALANCE = 0;
    uint256 public constant PENDING_BALANCE = 0;

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

    function setTimeToFrame0(MultiHashConsensusWithTimer consensus) public {
        consensus.setTimeInEpochs(INITIAL_EPOCH);
    }

    function getFastLaneLengthSlotsLimit(MultiHashConsensusWithTimer consensus)
        public
        view
        returns (uint256 fastLaneLengthSlotsLimit)
    {
        (, uint256 epochsPerFrame,) = consensus.getFrameConfig();
        (uint256 slotsPerEpoch,,) = consensus.getChainConfig();
        fastLaneLengthSlotsLimit = slotsPerEpoch * epochsPerFrame;
    }

    function hashArr1() public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](3);
        hashArr[0] = HASH_1;
        hashArr[1] = HASH_2;
        hashArr[2] = HASH_3;
        return hashArr;
    }

    function hashArr2() public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](3);
        hashArr[0] = HASH_1;
        hashArr[1] = HASH_3;
        hashArr[2] = HASH_2;
        return hashArr;
    }

    function hashArrZero() public pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function deployMultiHashConsensusMock() public returns (MultiHashConsensusWithTimer) {
        MultiHashConsensusWithTimer consensus = new MultiHashConsensusWithTimer();
        consensus.initialize(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            EPOCHS_PER_FRAME,
            INITIAL_FAST_LANE_LENGTH_SLOTS,
            DAO,
            address(0)
        );

        return consensus;
    }
}
