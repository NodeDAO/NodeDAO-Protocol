// SPDX-FileCopyrightText: 2023 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

import "src/library/UnstructuredStorage.sol";
import "src/oracles/BaseOracle.sol";

struct ConsensusReport {
    bytes32 hash;
    uint64 refSlot;
    uint64 processingDeadlineTime;
}

contract BaseOracleWithTimer is BaseOracle {
    using UnstructuredStorage for bytes32;

    uint256 internal _time = 2513040315;

    event MockStartProcessingResult(uint256 prevProcessingRefSlot);

    struct HandleConsensusReportLastCall {
        ConsensusReport report;
        uint256 prevSubmittedRefSlot;
        uint256 prevProcessingRefSlot;
        uint256 callCount;
    }

    HandleConsensusReportLastCall internal _handleConsensusReportLastCall;

    function _getTime() internal view override returns (uint256) {
        return _time;
    }

    function getTime() external view returns (uint256) {
        return _time;
    }

    function setTime(uint256 newTime) external {
        _time = newTime;
    }

    function advanceTimeBy(uint256 timeAdvance) external {
        _time += timeAdvance;
    }

    function _handleConsensusReport(
        ConsensusReport memory report,
        uint256 prevSubmittedRefSlot,
        uint256 prevProcessingRefSlot
    ) internal virtual override {
        _handleConsensusReportLastCall.report = report;
        _handleConsensusReportLastCall.prevSubmittedRefSlot = prevSubmittedRefSlot;
        _handleConsensusReportLastCall.prevProcessingRefSlot = prevProcessingRefSlot;
        ++_handleConsensusReportLastCall.callCount;
    }

    function getConsensusReportLastCall() external view returns (HandleConsensusReportLastCall memory) {
        return _handleConsensusReportLastCall;
    }

    function startProcessing() external {
        uint256 _res = _startProcessing();
        emit MockStartProcessingResult(_res);
    }

    function isConsensusMember(address addr) external view returns (bool) {
        return _isConsensusMember(addr);
    }

    function getCurrentRefSlot() external view returns (uint256) {
        return _getCurrentRefSlot();
    }

    function checkConsensusData(uint256 refSlot, uint256 consensusVersion, bytes32 hash) external view {
        _checkConsensusData(refSlot, consensusVersion, hash);
    }
}
