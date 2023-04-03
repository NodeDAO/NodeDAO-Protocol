// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts/utils/math/SafeCast.sol";
import "src/library/UnstructuredStorage.sol";
import "src/oracles/BaseOracle.sol";
import "src/interfaces/IBalanceOracle.sol";

contract BalanceOracle is IBalanceOracle, BaseOracle {
    using UnstructuredStorage for bytes32;
    using SafeCast for uint256;

    event WarnDataIncompleteProcessing(uint256 indexed refSlot);
    event PendingBalancesAdd(uint256 _addBalance, uint256 _totalBalance);
    event PendingBalancesReset(uint256 _totalBalance);
    event LiquidStakingChanged(address _before, address _after);
    event BalanceOracleReport(uint256 indexed refSlot, uint256 clBalances, uint256 clVaultBalance);

    error SenderNotAllowed();
    error InvalidRequestsData();

    struct DataProcessingState {
        uint64 refSlot;
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
    }

    ///
    /// Data provider interface
    ///
    struct ReportData {
        /// @dev Version of the oracle consensus rules. Current version expected
        /// by the oracle can be obtained by calling getConsensusVersion().
        uint256 consensusVersion;
        /// @dev Reference slot for which the report was calculated. If the slot
        /// contains a block, the exitBlockNumbers being reported should include all state
        /// changes resulting from that block. The epoch containing the slot
        /// should be finalized prior to calculating the report.
        // beacon slot for reference
        uint256 refSlot;
        /// Consensus layer NodeDao's validators balance
        uint256 clBalance;
        // Consensus Vault contract balance
        uint256 clVaultBalance;
    }

    /// @dev Storage slot: DataProcessingState dataProcessingState
    bytes32 internal constant DATA_PROCESSING_STATE_POSITION = keccak256("BalanceOracle.dataProcessingState");

    // current pending balance
    uint256 public pendingBalances;

    uint256 public clBalances;

    address public liquidStakingContractAddress;

    modifier onlyLiquidStaking() {
        require(liquidStakingContractAddress == msg.sender, "Not allowed onlyLiquidStaking");
        _;
    }

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

    /**
     * @return The total balance of the consensus layer
     */
    function getClBalances() external view returns (uint256) {
        return clBalances;
    }

    /**
     * @return The total balance of the pending validators
     */
    function getPendingBalances() external view returns (uint256) {
        return pendingBalances;
    }

    /**
     * @notice add pending validator value
     */
    function addPendingBalances(uint256 _pendingBalance) external onlyLiquidStaking {
        pendingBalances += _pendingBalance;
        emit PendingBalancesAdd(_pendingBalance, pendingBalances);
    }

    /**
     * @notice set LiquidStaking contract address
     * @param _liquidStakingContractAddress - contract address
     */
    function setLiquidStaking(address _liquidStakingContractAddress) external onlyDao {
        require(_liquidStakingContractAddress != address(0), "LiquidStaking address invalid");
        emit LiquidStakingChanged(liquidStakingContractAddress, _liquidStakingContractAddress);
        liquidStakingContractAddress = _liquidStakingContractAddress;
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
    }

    function _checkMsgSenderIsAllowedToSubmitData() internal view {
        address sender = _msgSender();
        if (!_isConsensusMember(sender)) {
            revert SenderNotAllowed();
        }
    }

    // todo
    function _handleConsensusReportData(ReportData calldata data) internal {
        // todo 调用结算

        pendingBalances = 0;
        emit PendingBalancesReset(0);
        _storageDataProcessingState().value = DataProcessingState({refSlot: data.refSlot.toUint64()});
        emit BalanceOracleReport(data.refSlot, data.clBalance, data.clVaultBalance);
    }

    // use for submitConsensusReport
    function _handleConsensusReport(
        ConsensusReport memory, /* report */
        uint256, /* prevSubmittedRefSlot */
        uint256 prevProcessingRefSlot
    ) internal override {
        DataProcessingState memory state = _storageDataProcessingState().value;
        if (state.refSlot == prevProcessingRefSlot) {
            emit WarnDataIncompleteProcessing(prevProcessingRefSlot);
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
