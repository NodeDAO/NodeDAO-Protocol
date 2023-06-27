// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/BaseOracle.sol";
import "src/interfaces/ILargeStaking.sol";
import {CLStakingInfo, CLStakingSlashInfo} from "src/library/ConsensusStruct.sol";

contract LargeStakeOracle is BaseOracle {
    event LargeStakeContractChanged(address oldLargeStake, address newLargeStake);
    event ReportSuccess(
        uint256 indexed refSlot,
        uint256 consensusVersion,
        CLStakingInfo[] cLStakingInfos,
        CLStakingSlashInfo[] cLStakingSlashInfos
    );

    error ReportDataIsEmpty();

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
    }

    /// Data provider interface
    struct ReportData {
        // @dev Version of the oracle consensus rules. Current version expected
        // by the oracle can be obtained by calling getConsensusVersion().
        uint256 consensusVersion;
        // @dev Reference slot for which the report was calculated. If the slot
        // contains a block, the exitBlockNumbers being reported should include all state
        // changes resulting from that block. The epoch containing the slot
        // should be finalized prior to calculating the report.
        // beacon slot for reference
        uint256 refSlot;
        // @dev Validator quits reporting information.
        // Only validator exits are reported.
        CLStakingInfo[] clStakingInfos;
        // @dev Verifier slash reporting information.
        // Only validator slash are reported.
        CLStakingSlashInfo[] clStakingSlashInfos;
    }

    address public largeStakeContract;

    function initialize(
        uint256 secondsPerSlot,
        uint256 genesisTime,
        address consensusContract,
        uint256 consensusVersion,
        uint256 lastProcessingRefSlot,
        address _dao,
        address _largeStakeContract
    ) public initializer {
        __BaseOracle_init(secondsPerSlot, genesisTime, consensusContract, consensusVersion, lastProcessingRefSlot, _dao);
        largeStakeContract = _largeStakeContract;
    }

    /**
     * @notice set LargeStake contract address
     */
    function setLargeStakeContract(address _largeStakeContractAddress) external onlyDao {
        if (_largeStakeContractAddress == address(0)) revert InvalidAddr();
        emit LargeStakeContractChanged(largeStakeContract, _largeStakeContractAddress);
        largeStakeContract = _largeStakeContractAddress;
    }

    /// @notice Returns data processing state for the current reporting frame.
    /// @return result See the docs for the `ProcessingState` struct.
    function getProcessingState() external view returns (ProcessingState memory result) {
        ConsensusReport memory report = consensusReport;
        result.currentFrameRefSlot = _getCurrentRefSlot();

        if (result.currentFrameRefSlot != report.refSlot) {
            return result;
        }

        result.processingDeadlineTime = report.processingDeadlineTime;
        result.dataHash = report.hash;

        result.dataSubmitted = lastProcessingRefSlot == result.currentFrameRefSlot;
        if (!result.dataSubmitted) {
            return result;
        }
    }

    /// @notice Submits report data for processing.
    ///
    /// @param data The data. See the `ReportData` structure's docs for details.
    /// @param _contractVersion Expected version of the oracle contract.
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
    function submitReportData(ReportData calldata data, uint256 _contractVersion, uint256 _moduleId)
        external
        whenNotPaused
    {
        _checkMsgSenderIsAllowedToSubmitData();
        _checkContractVersion(_contractVersion);
        // it's a waste of gas to copy the whole calldata into mem but seems there's no way around
        _checkConsensusData(data.refSlot, data.consensusVersion, keccak256(abi.encode(data)), _moduleId);
        _startProcessing();
        _handleConsensusReportData(data);
    }

    function _handleConsensusReportData(ReportData calldata data) internal {
        if (data.clStakingInfos.length == 0 && data.clStakingSlashInfos.length == 0) {
            revert ReportDataIsEmpty();
        }
        ILargeStaking(largeStakeContract).reportCLStakingData(data.clStakingInfos, data.clStakingSlashInfos);

        emit ReportSuccess(data.refSlot, data.consensusVersion, data.clStakingInfos, data.clStakingSlashInfos);
    }

    /// @notice Called when oracle gets a new consensus report from the HashConsensus contract.
    ///
    /// Keep in mind that, until you call `_startProcessing`, the oracle committee is free to
    /// reach consensus on another report for the same reporting frame and re-submit it using
    /// this function.
    ///
    function _handleConsensusReport(
        ConsensusReport memory report,
        uint256 prevSubmittedRefSlot,
        uint256 prevProcessingRefSlot
    ) internal override {}
}
