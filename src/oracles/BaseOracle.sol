// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

import "openzeppelin-contracts/utils/math/SafeCast.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/library/UnstructuredStorage.sol";
import "src/utils/Versioned.sol";
import "src/utils/Dao.sol";
import {IReportAsyncProcessor} from "src/oracles/HashConsensus.sol";

interface IConsensusContract {
    function getIsMember(address addr) external view returns (bool);

    function getCurrentFrame() external view returns (uint256 refSlot, uint256 reportProcessingDeadlineSlot);

    function getChainConfig()
        external
        view
        returns (uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime);

    function getFrameConfig() external view returns (uint256 initialEpoch, uint256 epochsPerFrame);

    function getInitialRefSlot() external view returns (uint256);
}

abstract contract BaseOracle is OwnableUpgradeable, UUPSUpgradeable, Dao, Versioned, IReportAsyncProcessor {
    using UnstructuredStorage for bytes32;
    using SafeCast for uint256;

    error AddressCannotBeZero();
    error AddressCannotBeSame();
    error VersionCannotBeSame();
    error UnexpectedChainConfig();
    error OnlyConsensusContractCanSubmitReport();
    error InitialRefSlotCannotBeLessThanProcessingOne(uint256 initialRefSlot, uint256 processingRefSlot);
    error RefSlotMustBeGreaterThanProcessingOne(uint256 refSlot, uint256 processingRefSlot);
    error RefSlotCannotDecrease(uint256 refSlot, uint256 prevRefSlot);
    error ProcessingDeadlineMissed(uint256 deadline);
    error RefSlotAlreadyProcessing();
    error UnexpectedRefSlot(uint256 consensusRefSlot, uint256 dataRefSlot);
    error UnexpectedConsensusVersion(uint256 expectedVersion, uint256 receivedVersion);
    error UnexpectedDataHash(bytes32 consensusHash, bytes32 receivedHash);

    event ConsensusHashContractSet(address indexed addr, address indexed prevAddr);
    event ConsensusVersionSet(uint256 indexed version, uint256 indexed prevVersion);
    event ReportSubmitted(uint256 indexed refSlot, bytes32 hash, uint256 processingDeadlineTime);
    event ProcessingStarted(uint256 indexed refSlot, bytes32 hash);
    event WarnProcessingMissed(uint256 indexed refSlot);

    struct ConsensusReport {
        bytes32 hash;
        uint64 refSlot;
        uint64 processingDeadlineTime;
    }

    /// @dev Storage slot: address consensusContract
    bytes32 internal constant CONSENSUS_CONTRACT_POSITION = keccak256("BaseOracle.consensusContract");

    /// @dev Storage slot: uint256 consensusVersion
    bytes32 internal constant CONSENSUS_VERSION_POSITION = keccak256("BaseOracle.consensusVersion");

    /// @dev Storage slot: uint256 lastProcessingRefSlot
    bytes32 internal constant LAST_PROCESSING_REF_SLOT_POSITION = keccak256("BaseOracle.lastProcessingRefSlot");

    /// @dev Storage slot: ConsensusReport consensusReport
    bytes32 internal constant CONSENSUS_REPORT_POSITION = keccak256("BaseOracle.consensusReport");

    uint256 public SECONDS_PER_SLOT;
    uint256 public GENESIS_TIME;

    ///
    /// Descendant contract interface
    ///

    /// @notice Initializes the contract storage. Must be called by a descendant
    /// contract as part of its initialization.
    ///
    function __BaseOracle_init(
        uint256 secondsPerSlot,
        uint256 genesisTime,
        address consensusContract,
        uint256 consensusVersion,
        uint256 lastProcessingRefSlot,
        address _dao
    ) internal virtual onlyInitializing {
        __Ownable_init();
        __UUPSUpgradeable_init();

        if (_dao == address(0)) revert DaoCannotBeZero();
        dao = _dao;
        SECONDS_PER_SLOT = secondsPerSlot;
        GENESIS_TIME = genesisTime;

        _initializeContractVersionTo(1);
        _setConsensusContract(consensusContract, lastProcessingRefSlot);
        _setConsensusVersion(consensusVersion);
        LAST_PROCESSING_REF_SLOT_POSITION.setStorageUint256(lastProcessingRefSlot);
        _storageConsensusReport().value.refSlot = lastProcessingRefSlot.toUint64();
    }

    // set dao vault address
    function setDaoAddress(address _dao) external override onlyOwner {
        require(_dao != address(0), "Dao address invalid");
        emit DaoAddressChanged(dao, _dao);
        dao = _dao;
    }

    /// @notice Returns the address of the HashConsensus contract.
    ///
    function getConsensusContract() external view returns (address) {
        return CONSENSUS_CONTRACT_POSITION.getStorageAddress();
    }

    /// @notice Sets the address of the HashConsensus contract.
    ///
    function setConsensusContract(address addr) external onlyOwner {
        _setConsensusContract(addr, LAST_PROCESSING_REF_SLOT_POSITION.getStorageUint256());
    }

    /// @notice Returns the current consensus version expected by the oracle contract.
    ///
    /// Consensus version must change every time consensus rules change, meaning that
    /// an oracle looking at the same reference slot would calculate a different hash.
    ///
    function getConsensusVersion() external view returns (uint256) {
        return CONSENSUS_VERSION_POSITION.getStorageUint256();
    }

    /// @notice Sets the consensus version expected by the oracle contract.
    ///
    function setConsensusVersion(uint256 version) external onlyDao {
        _setConsensusVersion(version);
    }

    ///
    /// Data provider interface
    ///

    /// @notice Returns the last consensus report hash and metadata.
    ///
    function getConsensusReport()
        external
        view
        returns (bytes32 hash, uint256 refSlot, uint256 processingDeadlineTime, bool processingStarted)
    {
        ConsensusReport memory report = _storageConsensusReport().value;
        uint256 processingRefSlot = LAST_PROCESSING_REF_SLOT_POSITION.getStorageUint256();
        return (
            report.hash,
            report.refSlot,
            report.processingDeadlineTime,
            report.hash != bytes32(0) && report.refSlot == processingRefSlot
        );
    }

    ///
    /// Consensus contract interface
    ///

    /// @notice Called by HashConsensus contract to push a consensus report for processing.
    ///
    /// Note that submitting the report doesn't require the oracle to start processing it
    /// right away, this can happen later. Until the processing is started, HashConsensus is
    /// free to reach consensus on another report for the same reporting frame and submit it
    /// using this same function.
    ///
    function submitConsensusReport(bytes32 reportHash, uint256 refSlot, uint256 deadline) external {
        if (_msgSender() != CONSENSUS_CONTRACT_POSITION.getStorageAddress()) {
            revert OnlyConsensusContractCanSubmitReport();
        }

        uint256 prevSubmittedRefSlot = _storageConsensusReport().value.refSlot;
        if (refSlot < prevSubmittedRefSlot) {
            revert RefSlotCannotDecrease(refSlot, prevSubmittedRefSlot);
        }

        uint256 prevProcessingRefSlot = LAST_PROCESSING_REF_SLOT_POSITION.getStorageUint256();
        if (refSlot <= prevProcessingRefSlot) {
            revert RefSlotMustBeGreaterThanProcessingOne(refSlot, prevProcessingRefSlot);
        }

        if (refSlot != prevSubmittedRefSlot && prevProcessingRefSlot != prevSubmittedRefSlot) {
            emit WarnProcessingMissed(prevSubmittedRefSlot);
        }

        emit ReportSubmitted(refSlot, reportHash, deadline);

        ConsensusReport memory report = ConsensusReport({
            hash: reportHash,
            refSlot: refSlot.toUint64(),
            processingDeadlineTime: deadline.toUint64()
        });

        _storageConsensusReport().value = report;
        _handleConsensusReport(report, prevSubmittedRefSlot, prevProcessingRefSlot);
    }

    /// @notice Returns the last reference slot for which processing of the report was started.
    ///
    function getLastProcessingRefSlot() external view returns (uint256) {
        return LAST_PROCESSING_REF_SLOT_POSITION.getStorageUint256();
    }

    /// @notice Returns whether the given address is a member of the oracle committee.
    ///
    function _isConsensusMember(address addr) internal view returns (bool) {
        address consensus = CONSENSUS_CONTRACT_POSITION.getStorageAddress();
        return IConsensusContract(consensus).getIsMember(addr);
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
    ) internal virtual;

    /// @notice May be called by a descendant contract to check if the received data matches
    /// the currently submitted consensus report, and that processing deadline is not missed.
    /// Reverts otherwise.
    ///
    function _checkConsensusData(uint256 refSlot, uint256 consensusVersion, bytes32 hash) internal view {
        // If the processing deadline for the current consensus report is missed, an error is reported
        _checkProcessingDeadline();

        ConsensusReport memory report = _storageConsensusReport().value;
        if (refSlot != report.refSlot) {
            revert UnexpectedRefSlot(report.refSlot, refSlot);
        }

        uint256 expectedConsensusVersion = CONSENSUS_VERSION_POSITION.getStorageUint256();
        if (consensusVersion != expectedConsensusVersion) {
            revert UnexpectedConsensusVersion(expectedConsensusVersion, consensusVersion);
        }

        if (hash != report.hash) {
            revert UnexpectedDataHash(report.hash, hash);
        }
    }

    /// @notice Called by a descendant contract to mark the current consensus report
    /// as being processed. Returns the last ref. slot which processing was started
    /// before the call.
    ///
    /// Before this function is called, the oracle committee is free to reach consensus
    /// on another report for the same reporting frame. After this function is called,
    /// the consensus report for the current frame is guaranteed to remain the same.
    ///
    function _startProcessing() internal returns (uint256) {
        _checkProcessingDeadline();

        ConsensusReport memory report = _storageConsensusReport().value;

        // If the slot has been reported, an error is reported
        uint256 prevProcessingRefSlot = LAST_PROCESSING_REF_SLOT_POSITION.getStorageUint256();
        if (prevProcessingRefSlot == report.refSlot) {
            revert RefSlotAlreadyProcessing();
        }

        LAST_PROCESSING_REF_SLOT_POSITION.setStorageUint256(report.refSlot);

        emit ProcessingStarted(report.refSlot, report.hash);
        return prevProcessingRefSlot;
    }

    /// @notice Reverts if the processing deadline for the current consensus report is missed.
    ///
    function _checkProcessingDeadline() internal view {
        uint256 deadline = _storageConsensusReport().value.processingDeadlineTime;
        if (_getTime() > deadline) revert ProcessingDeadlineMissed(deadline);
    }

    /// @notice Returns the reference slot for the current frame.
    ///
    function _getCurrentRefSlot() internal view returns (uint256) {
        address consensusContract = CONSENSUS_CONTRACT_POSITION.getStorageAddress();
        (uint256 refSlot,) = IConsensusContract(consensusContract).getCurrentFrame();
        return refSlot;
    }

    ///
    /// Implementation & helpers
    ///

    function _setConsensusVersion(uint256 version) internal {
        uint256 prevVersion = CONSENSUS_VERSION_POSITION.getStorageUint256();
        if (version == prevVersion) revert VersionCannotBeSame();
        CONSENSUS_VERSION_POSITION.setStorageUint256(version);
        emit ConsensusVersionSet(version, prevVersion);
    }

    function _setConsensusContract(address addr, uint256 lastProcessingRefSlot) internal {
        if (addr == address(0)) revert AddressCannotBeZero();

        address prevAddr = CONSENSUS_CONTRACT_POSITION.getStorageAddress();
        if (addr == prevAddr) revert AddressCannotBeSame();

        (, uint256 secondsPerSlot, uint256 genesisTime) = IConsensusContract(addr).getChainConfig();
        if (secondsPerSlot != SECONDS_PER_SLOT || genesisTime != GENESIS_TIME) {
            revert UnexpectedChainConfig();
        }

        uint256 initialRefSlot = IConsensusContract(addr).getInitialRefSlot();
        if (initialRefSlot < lastProcessingRefSlot) {
            revert InitialRefSlotCannotBeLessThanProcessingOne(initialRefSlot, lastProcessingRefSlot);
        }

        CONSENSUS_CONTRACT_POSITION.setStorageAddress(addr);
        emit ConsensusHashContractSet(addr, prevAddr);
    }

    function _getTime() internal view virtual returns (uint256) {
        return block.timestamp; // solhint-disable-line not-rely-on-time
    }

    ///
    /// Storage helpers
    ///

    struct StorageConsensusReport {
        ConsensusReport value;
    }

    function _storageConsensusReport() internal pure returns (StorageConsensusReport storage r) {
        bytes32 position = CONSENSUS_REPORT_POSITION;
        assembly {
            r.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
