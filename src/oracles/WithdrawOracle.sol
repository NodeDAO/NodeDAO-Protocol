// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts/utils/math/SafeCast.sol";
import "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import "src/library/UnstructuredStorage.sol";
import "src/oracles/BaseOracle.sol";

contract WithdrawOracle is BaseOracle {
    using UnstructuredStorage for bytes32;
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    event WarnDataIncompleteProcessing(uint256 indexed refSlot, uint256 exitRequestLimit, uint256 reportExitedCount);
    event UpdateExitRequestLimit(uint256 exitRequestLimit);

    error SenderNotAllowed();
    error UnsupportedRequestsDataFormat(uint256 format);
    error InvalidRequestsData();
    error InvalidRequestsDataLength();
    error UnexpectedRequestsDataLength();
    error ArgumentOutOfBounds();
    error ExitRequestLimitNotZero();
    error ValidatorReportedExit(uint256 tokenId);

    struct WithdrawInfo {
        uint256 operatorId;
        // The income that should be issued by this operatorId in this settlement
        uint128 clRewards;
        // For this settlement, whether operatorId has exit node, if no exit node is 0;
        // The value of one node exiting is 32 eth(or 32.9 ETH), and the value of two nodes exiting is 64eth (or 63 ETH).
        // If the value is less than 32, the corresponding amount will be punished
        uint128 clCapital;
    }

    struct DataProcessingState {
        uint64 refSlot;
        uint64 reportExitedCount;
        uint16 dataFormat;
    }

    struct ProcessingState {
        /// @notice Reference slot for the current reporting frame.
        uint256 currentFrameRefSlot;
        /// @notice The last time at which a report data can be submitted for the current
        /// reporting frame.
        uint256 processingDeadlineTime;
        /// @notice Hash of the report data. Zero bytes if consensus on the hash hasn't
        /// been reached yet for the current reporting frame.
        bytes32 dataHash;
        /// @notice Whether any report data for the for the current reporting frame has been
        /// already submitted.
        bool dataSubmitted;
        /// @notice Format of the report data for the current reporting frame.
        uint256 dataFormat;
        /// @notice Number of exits reported for the current reporting frame.
        uint256 reportExitedCount;
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
        /// Number of exits reported
        uint256 reportExitedCount;
        ///
        /// Report core data
        ///
        WithdrawInfo[] withdrawInfos;
        // Example Exit the token Id of the validator. No exit is an empty array.
        uint256[] exitTokenIds;
        // Height of exit block
        uint256[] exitBlockNumbers;
        /// @dev Format of the validator exit requests data. Currently, only the
        /// DATA_FORMAT_LIST=1 is supported.
        // See: Defined data format types
        uint256 dataFormat;
        /// @dev Validator exit requests data. Can differ based on the data format,
        /// see the constant defining a specific data format below for more info.
        // See the data format constant DATA_FORMAT_LIST
        bytes data;
    }

    /// @notice The list format of the validator exit requests data. Used when all
    /// requests fit into a single transaction.
    ///
    /// Each validator exit request is described by the following 64-byte array:
    /// todo 如果需要包装，重新设计字节占用
    /// MSB <------------------------------------------------------- LSB
    /// |  3 bytes   |  5 bytes   |     8 bytes      |    48 bytes     |
    /// |  moduleId  |  nodeOpId  |  validatorIndex  | validatorPubkey |
    ///
    /// All requests are tightly packed into a byte array where requests follow
    /// one another without any separator or padding, and passed to the `data`
    /// field of the report structure.
    ///
    /// Requests must be sorted in the ascending order by the following compound
    /// key: (moduleId, nodeOpId, validatorIndex).
    /// Wrap the transaction extra content as an array
    uint256 public constant DATA_FORMAT_LIST = 1;

    /// Length in bytes of packed request
    // todo 如果需要重新定义长度
    uint256 internal constant PACKED_REQUEST_LENGTH = 64;

    /// @dev Storage slot: DataProcessingState dataProcessingState
    bytes32 internal constant DATA_PROCESSING_STATE_POSITION = keccak256("WithdrawOracle.dataProcessingState");

    // Specifies the maximum number of validator exits reported each time
    uint256 public exitRequestLimit = 1000;

    // The exited validators
    EnumerableSet.UintSet internal exitedTokenIds;

    function initialize(
        uint256 secondsPerSlot,
        uint256 genesisTime,
        address consensusContract,
        uint256 consensusVersion,
        uint256 lastProcessingRefSlot,
        address _dao
    ) public initializer {
        __BaseOracle_init(secondsPerSlot, genesisTime, consensusContract, consensusVersion, lastProcessingRefSlot, _dao);
    }

    /// Set the number limit for the validator to report
    function setExitRequestLimit(uint256 _exitRequestLimit) external onlyDao {
        if (_exitRequestLimit == 0) revert ExitRequestLimitNotZero();
        exitRequestLimit = _exitRequestLimit;
        emit UpdateExitRequestLimit(_exitRequestLimit);
    }

    /// @notice Submits report data for processing.
    ///
    /// @param data The data. See the `ReportData` structure's docs for details.
    /// @param contractVersion Expected version of the oracle contract.
    ///
    /// Reverts if:
    /// - The caller is not a member of the oracle committee and doesn't possess the
    ///   SUBMIT_DATA_ROLE.
    /// - The provided contract version is different from the current one.
    /// - The provided consensus version is different from the expected one.
    /// - The provided reference slot differs from the current consensus frame's one.
    /// - The processing deadline for the current consensus frame is missed.
    /// - The keccak256 hash of the ABI-encoded data is different from the last hash
    ///   provided by the hash consensus contract.
    /// - The provided data doesn't meet safety checks.
    function submitReportData(ReportData calldata data, uint256 contractVersion) external {
        _checkMsgSenderIsAllowedToSubmitData();
        _checkContractVersion(contractVersion);
        // it's a waste of gas to copy the whole calldata into mem but seems there's no way around
        _checkConsensusData(data.refSlot, data.consensusVersion, keccak256(abi.encode(data)));
        _startProcessing();
        _handleConsensusReportData(data);
    }

    /// @notice Returns data processing state for the current reporting frame.
    /// @return result See the docs for the `ProcessingState` struct.
    /// todo
    function getProcessingState() external view returns (ProcessingState memory result) {
        ConsensusReport memory report = _storageConsensusReport().value;
        result.currentFrameRefSlot = _getCurrentRefSlot();

        if (result.currentFrameRefSlot != report.refSlot) {
            return result;
        }

        result.processingDeadlineTime = report.processingDeadlineTime;
        result.dataHash = report.hash;

        DataProcessingState memory procState = _storageDataProcessingState().value;

        result.dataSubmitted = procState.refSlot == result.currentFrameRefSlot;
        if (!result.dataSubmitted) {
            return result;
        }

        result.dataFormat = procState.dataFormat;
        result.reportExitedCount = procState.reportExitedCount;
    }

    function _checkMsgSenderIsAllowedToSubmitData() internal view {
        address sender = _msgSender();
        if (!_isConsensusMember(sender)) {
            revert SenderNotAllowed();
        }
    }

    // todo
    function _handleConsensusReportData(ReportData calldata data) internal {
        if (data.dataFormat != DATA_FORMAT_LIST) {
            revert UnsupportedRequestsDataFormat(data.dataFormat);
        }

        // Data format exception that does not match the number of bytes of each element in the array
        //        if (data.data.length % PACKED_REQUEST_LENGTH != 0) {
        //            revert InvalidRequestsDataLength();
        //        }

        if (
            data.exitTokenIds.length != data.reportExitedCount || data.exitBlockNumbers.length != data.reportExitedCount
        ) {
            revert InvalidRequestsDataLength();
        }

        // Add to a list that has exited validator (de-weight)
        uint256[] calldata _exitTokenIds = data.exitTokenIds;
        for (uint256 i = 0; i < _exitTokenIds.length; ++i) {
            // Add the token ids of the validator to the list. If an error occurs, the Validator is added
            if (exitedTokenIds.add(_exitTokenIds[i])) {
                revert ValidatorReportedExit(_exitTokenIds[i]);
            }
        }

        // todo 调用结算

        // 退出数量不一致 报错
        //        if (data.data.length / PACKED_REQUEST_LENGTH != data.requestsCount) {
        //            revert UnexpectedRequestsDataLength();
        //        }

        // todo 退出请求列表处理 如果数据需要包装 那么 再做实现
        //        _processExitRequestsList(data.data);

        _storageDataProcessingState().value = DataProcessingState({
            refSlot: data.refSlot.toUint64(),
            reportExitedCount: data.reportExitedCount.toUint64(),
            dataFormat: uint16(DATA_FORMAT_LIST)
        });
    }

    // use for submitConsensusReport
    function _handleConsensusReport(
        ConsensusReport memory, /* report */
        uint256, /* prevSubmittedRefSlot */
        uint256 prevProcessingRefSlot
    ) internal override {
        DataProcessingState memory state = _storageDataProcessingState().value;
        if (state.refSlot == prevProcessingRefSlot && state.reportExitedCount <= exitRequestLimit) {
            emit WarnDataIncompleteProcessing(prevProcessingRefSlot, exitRequestLimit, state.reportExitedCount);
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
