// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

import {IReportAsyncProcessor} from "src/oracles/MultiHashConsensus.sol";

contract MockMultiReportProcessor is IReportAsyncProcessor {
    error ModuleIdNotEqual();

    uint256 internal _consensusVersion;
    uint256 public moduleId;

    struct SubmitReportLastCall {
        bytes32 report;
        uint256 refSlot;
        uint256 deadline;
        uint256 callCount;
    }

    SubmitReportLastCall internal _submitReportLastCall;
    uint256 internal _lastProcessingRefSlot;

    constructor(uint256 consensusVersion, uint256 _moduleId) {
        _consensusVersion = consensusVersion;
        moduleId = _moduleId;
    }

    function setConsensusVersion(uint256 consensusVersion) external {
        _consensusVersion = consensusVersion;
    }

    function setLastProcessingStartedRefSlot(uint256 refSlot) external {
        _lastProcessingRefSlot = refSlot;
    }

    function getLastCall_submitReport() external view returns (SubmitReportLastCall memory) {
        return _submitReportLastCall;
    }

    function startReportProcessing() external {
        _lastProcessingRefSlot = _submitReportLastCall.refSlot;
    }

    ///
    /// IReportAsyncProcessor
    ///

    function getConsensusVersion() external view returns (uint256) {
        return _consensusVersion;
    }

    function submitConsensusReport(bytes32 report, uint256 refSlot, uint256 deadline, uint256 _moduleId) external {
        _submitReportLastCall.report = report;
        _submitReportLastCall.refSlot = refSlot;
        _submitReportLastCall.deadline = deadline;
        ++_submitReportLastCall.callCount;
        if (_moduleId != moduleId) {
            revert ModuleIdNotEqual();
        }
    }

    function getLastProcessingRefSlot() external view returns (uint256) {
        return _lastProcessingRefSlot;
    }
}
