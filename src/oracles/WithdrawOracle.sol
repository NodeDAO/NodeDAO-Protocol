// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/BaseOracle.sol";

contract WithdrawOracle is BaseOracle {
    event WarnDataIncompleteProcessing(uint256 indexed refSlot, uint256 requestsProcessed, uint256 requestsCount);

    struct WithdrawInfo {
        uint256 operatorId;
        // The income that should be issued by this operatorId in this settlement
        uint128 clRewards;
        // For this settlement, whether operatorId has exit node, if no exit node is 0;
        // The value of one node exiting is 32 eth(or 32.9 ETH), and the value of two nodes exiting is 64eth (or 63 ETH).
        // If the value is less than 32, the corresponding amount will be punished
        uint128 clCapital;
        // Whether the operatorId has an exit node in this solution; No exit is an empty array
        uint256[] exitTokenIds;
    }

    struct DataProcessingState {
        uint64 refSlot;
        uint64 requestsCount;
        uint64 requestsProcessed;
        uint16 dataFormat;
    }

    ///
    /// Data provider interface
    ///

    struct ReportData {
        ///
        /// Oracle consensus info
        ///

        /// @dev Version of the oracle consensus rules. Current version expected
        /// by the oracle can be obtained by calling getConsensusVersion().
        uint256 consensusVersion;
        /// @dev Reference slot for which the report was calculated. If the slot
        /// contains a block, the state being reported should include all state
        /// changes resulting from that block. The epoch containing the slot
        /// should be finalized prior to calculating the report.
        // beacon slot for reference
        uint256 refSlot;
        ///
        /// Requests data
        ///

        /// @dev Total number of validator exit requests in this report. Must not be greater
        /// than limit checked in OracleReportSanityChecker.checkExitBusOracleReport.
        ///
        /// Cannot be zero: in the case there's no validator exit requests to submit, oracles
        /// should skip submitting the report for the current reporting frame.
        /**
         * 本报告中验证器退出请求的总数。一定不能更大检查OracleReportSanityChecker.checkExitBusOracleReport。
         *    不能为零:在没有要提交的验证器退出请求的情况下，oracle应跳过提交当前报告框架的报告。
         */
        uint256 requestsCount;
        /// @dev Format of the validator exit requests data. Currently, only the
        /// DATA_FORMAT_LIST=1 is supported.
        // See: Defined data format types
        uint256 dataFormat;
        /// @dev Validator exit requests data. Can differ based on the data format,
        /// see the constant defining a specific data format below for more info.
        // See the data format constant DATA_FORMAT_LIST
        bytes data;
    }

    /// @dev Storage slot: uint256 totalRequestsProcessed
    bytes32 internal constant TOTAL_REQUESTS_PROCESSED_POSITION = keccak256("WithdrawOracle.totalRequestsProcessed");

    /// @dev Storage slot: mapping(uint256 => RequestedValidator) lastRequestedValidatorIndices
    /// A mapping from the (moduleId, nodeOpId) packed key to the last requested validator index.
    bytes32 internal constant LAST_REQUESTED_VALIDATOR_INDICES_POSITION =
        keccak256("WithdrawOracle.lastRequestedValidatorIndices");

    /// @dev Storage slot: DataProcessingState dataProcessingState
    bytes32 internal constant DATA_PROCESSING_STATE_POSITION = keccak256("WithdrawOracle.dataProcessingState");

    constructor(uint256 secondsPerSlot, uint256 genesisTime) BaseOracle(secondsPerSlot, genesisTime) {}

    function initialize(
        address consensusContract,
        uint256 consensusVersion,
        uint256 lastProcessingRefSlot,
        address _dao
    ) public initializer {
        __BaseOracle_init(consensusContract, consensusVersion, lastProcessingRefSlot, _dao);
    }

    function _handleConsensusReport(
        ConsensusReport memory, /* report */
        uint256, /* prevSubmittedRefSlot */
        uint256 prevProcessingRefSlot
    ) internal override {
        DataProcessingState memory state = _storageDataProcessingState().value;
        if (state.refSlot == prevProcessingRefSlot && state.requestsProcessed < state.requestsCount) {
            emit WarnDataIncompleteProcessing(prevProcessingRefSlot, state.requestsProcessed, state.requestsCount);
        }
    }

    struct StorageDataProcessingState {
        DataProcessingState value;
    }

    function _storageDataProcessingState() internal pure returns (StorageDataProcessingState storage r) {
        bytes32 position = DATA_PROCESSING_STATE_POSITION;
        assembly {
            r.slot := position
        }
    }
}
