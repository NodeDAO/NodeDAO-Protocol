// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

import "src/oracles/WithdrawOracle.sol";
import "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts/utils/math/SafeCast.sol";

interface ITimeProvider {
    function getTime() external view returns (uint256);
}

struct MockWithdrawInfo {
    uint256 operatorId;
    // The income that should be issued by this operatorId in this settlement
    uint128 clRewards;
    // For this settlement, whether operatorId has exit node, if no exit node is 0;
    // The value of one node exiting is 32 eth(or 32.9 ETH), and the value of two nodes exiting is 64eth (or 63 ETH).
    // If the value is less than 32, the corresponding amount will be punished
    uint128 clCapital;
}

contract WithdrawOracleWithTimer is WithdrawOracle {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.UintSet private exitedTokenIds;
    mapping(uint256 => bool) private exitedTokenIdMap;

    function getTime() external view returns (uint256) {
        return _getTime();
    }

    function _getTime() internal view override returns (uint256) {
        address consensus = consensusContract;
        return ITimeProvider(consensus).getTime();
    }

    function getDataProcessingState() external view returns (DataProcessingState memory) {
        return dataProcessingState;
    }

    struct ReportDataMock1 {
        ///
        /// Oracle consensus info
        ///

        /// @dev Version of the oracle consensus rules. Current version expected
        /// by the oracle can be obtained by calling getConsensusVersion().
        uint256 consensusVersion;
        /// @dev Reference slot for which the report was calculated. If the slot
        /// contains a block, the exitBlockNumbers being reported should include all state
        /// changes resulting from that block. The epoch containing the slot
        /// should be finalized prior to calculating the report.
        // beacon slot for reference
        uint256 refSlot;
        /// Number of exits reported
        uint256 reportExitedCount;
        ///
        /// Report core data
        ///
        MockWithdrawInfo[] withdrawInfos;
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

    function submitReportDataMock1(ReportDataMock1 calldata data, uint256 _contractVersion, uint256 _moduleId)
        external
    {
        _checkMsgSenderIsAllowedToSubmitData();
        _checkContractVersion(_contractVersion);
        // it's a waste of gas to copy the whole calldata into mem but seems there's no way around
        _checkConsensusData(data.refSlot, data.consensusVersion, keccak256(abi.encode(data)), _moduleId);
        _startProcessing();
        _handleConsensusReportDataMock1(data);
    }

    function _handleConsensusReportDataMock1(ReportDataMock1 calldata data) internal {
        if (
            data.exitTokenIds.length != data.reportExitedCount || data.exitBlockNumbers.length != data.reportExitedCount
        ) {
            revert InvalidRequestsDataLength();
        }

        dataProcessingState = DataProcessingState({
            refSlot: data.refSlot.toUint64(),
            reportExitedCount: data.reportExitedCount.toUint64()
        });
    }
}
