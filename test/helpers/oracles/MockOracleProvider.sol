// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockReportProcessor.sol";
import {WithdrawInfo, WithdrawOracleWithTimer} from "test/helpers/oracles/WithdrawOracleWithTimer.sol";
import "test/helpers/CommonConstantProvider.sol";

// Provide baseline data for the Hash Consensus contract test
contract MockOracleProvider is CommonConstantProvider {
    //    struct WithdrawInfo {
    //        uint256 operatorId;
    //        // The income that should be issued by this operatorId in this settlement
    //        uint128 clRewards;
    //        // For this settlement, whether operatorId has exit node, if no exit node is 0;
    //        // The value of one node exiting is 32 eth(or 32.9 ETH), and the value of two nodes exiting is 64eth (or 63 ETH).
    //        // If the value is less than 32, the corresponding amount will be punished
    //        uint128 clCapital;
    //    }

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

    uint256 public constant DATA_FORMAT_LIST = 1;
    uint256 public constant LAST_PROCESSING_REF_SLOT = 1;

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

    function deployWithdrawOracleMock() public returns (HashConsensusWithTimer, WithdrawOracleWithTimer) {
        HashConsensusWithTimer consensus = new HashConsensusWithTimer();
        WithdrawOracleWithTimer oracle = new WithdrawOracleWithTimer();
        consensus.initialize(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            EPOCHS_PER_FRAME,
            INITIAL_FAST_LANE_LENGTH_SLOTS,
            DAO,
            address(oracle)
        );

        oracle.initialize(SECONDS_PER_SLOT, GENESIS_TIME, address(consensus), CONSENSUS_VERSION, 0, DAO);

        return (consensus, oracle);
    }

    function mockWithdrawOracleReportData_1(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = 3;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](3);
        exitTokenIds[0] = 1;
        exitTokenIds[1] = 3;
        exitTokenIds[2] = 5;
        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](3);
        exitBlockNumbers[0] = 1000;
        exitBlockNumbers[1] = 1005;
        exitBlockNumbers[2] = 1010;
        reportData.exitBlockNumbers = exitBlockNumbers;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](2);

        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clRewards: 1e17, clCapital: 64 ether});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 2, clRewards: 1e16, clCapital: 31 ether});

        withdrawInfos[0] = withdrawInfo1;
        withdrawInfos[1] = withdrawInfo2;

        reportData.withdrawInfos = withdrawInfos;
    }

    function mockWithdrawOracleReportDataHash_1(uint256 refSlot) public pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(mockWithdrawOracleReportData_1(refSlot)));
    }

    function mockWithdrawOracleReportData_2(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = 2;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](2);
        exitTokenIds[0] = 1;
        exitTokenIds[1] = 3;
        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](2);
        exitBlockNumbers[0] = 1000;
        exitBlockNumbers[1] = 1005;
        reportData.exitBlockNumbers = exitBlockNumbers;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](2);

        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});

        withdrawInfos[0] = withdrawInfo1;
        withdrawInfos[1] = withdrawInfo2;

        reportData.withdrawInfos = withdrawInfos;
    }

    function mockWithdrawOracleReportDataHash_2(uint256 refSlot) public pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(mockWithdrawOracleReportData_2(refSlot)));
    }

    function mockWithdrawOracleReportData_3(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = 3;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](3);
        exitTokenIds[0] = 1;
        exitTokenIds[1] = 3;
        exitTokenIds[2] = 5;
        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](3);
        exitBlockNumbers[0] = 1000;
        exitBlockNumbers[1] = 1005;
        exitBlockNumbers[2] = 1010;
        reportData.exitBlockNumbers = exitBlockNumbers;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](2);

        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 4, clRewards: 1e16, clCapital: 31 ether});

        withdrawInfos[0] = withdrawInfo1;
        withdrawInfos[1] = withdrawInfo2;

        reportData.withdrawInfos = withdrawInfos;
    }

    function mockWithdrawOracleReportDataHash_3(uint256 refSlot) public pure returns (bytes32 hash) {
        hash = keccak256(abi.encode(mockWithdrawOracleReportData_3(refSlot)));
    }

    function mockDifferentStructHashIsSame() public pure returns (bool) {
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 4, clRewards: 1e16, clCapital: 31 ether});
        bytes32 hash1 = keccak256(abi.encode(withdrawInfo1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfo2));
        return hash1 == hash2;
    }

    function mockSameStructHashIsSame() public pure returns (bool) {
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});

        bytes32 hash1 = keccak256(abi.encode(withdrawInfo1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfo2));
        return hash1 == hash2;
    }

    function mockDifferentStructArrayHashIsSame() public pure returns (bool) {
        WithdrawInfo[] memory withdrawInfos1 = new WithdrawInfo[](2);
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});
        withdrawInfos1[0] = withdrawInfo1;
        withdrawInfos1[1] = withdrawInfo2;

        WithdrawInfo[] memory withdrawInfos2 = new WithdrawInfo[](2);
        WithdrawInfo memory withdrawInfo3 = WithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        WithdrawInfo memory withdrawInfo4 = WithdrawInfo({operatorId: 4, clRewards: 1e16, clCapital: 31 ether});
        withdrawInfos2[0] = withdrawInfo3;
        withdrawInfos2[1] = withdrawInfo4;

        bytes32 hash1 = keccak256(abi.encode(withdrawInfos1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfos2));
        return hash1 == hash2;
    }

    function mockSameStructArrayHashIsSame() public pure returns (bool) {
        WithdrawInfo[] memory withdrawInfos1 = new WithdrawInfo[](2);
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});
        withdrawInfos1[0] = withdrawInfo1;
        withdrawInfos1[1] = withdrawInfo2;

        WithdrawInfo[] memory withdrawInfos2 = new WithdrawInfo[](2);
        WithdrawInfo memory withdrawInfo3 = WithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        WithdrawInfo memory withdrawInfo4 = WithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});
        withdrawInfos2[0] = withdrawInfo3;
        withdrawInfos2[1] = withdrawInfo4;

        bytes32 hash1 = keccak256(abi.encode(withdrawInfos1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfos2));
        return hash1 == hash2;
    }

    function mockWithdrawOracleReportData_count(uint256 refSlot, uint256 exitCount, uint256 opsCount)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = exitCount;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](exitCount);
        for (uint256 i = 0; i < exitCount; ++i) {
            exitTokenIds[i] = i;
        }

        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](exitCount);
        for (uint256 i = 0; i < exitCount; ++i) {
            exitBlockNumbers[i] = 1001;
        }
        reportData.exitBlockNumbers = exitBlockNumbers;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](opsCount);
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        for (uint256 i = 0; i < opsCount; ++i) {
            withdrawInfos[i] = withdrawInfo1;
        }

        reportData.withdrawInfos = withdrawInfos;
    }

    function mockWithdrawOracleReportData_countHash(uint256 refSlot, uint256 exitCount, uint256 opsCount)
        public
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(abi.encode(mockWithdrawOracleReportData_count(refSlot, exitCount, opsCount)));
    }
}
