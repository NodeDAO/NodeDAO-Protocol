// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

interface ISSV {
    /**
     *
     */
    /* Structs */
    /**
     *
     */

    /// @notice Represents a snapshot of an operator's or a DAO's state at a certain block
    struct Snapshot {
        /// @dev The block number when the snapshot was taken
        uint32 block;
        /// @dev The last index calculated by the formula index += (currentBlock - block) * fee
        uint64 index;
        /// @dev Total accumulated earnings calculated by the formula accumulated + lastIndex * validatorCount
        uint64 balance;
    }

    /// @notice Represents an SSV operator
    struct Operator {
        /// @dev The number of validators associated with this operator
        uint32 validatorCount;
        /// @dev The fee charged by the operator, set to zero for private operators and cannot be increased once set
        uint64 fee;
        /// @dev The address of the operator's owner
        address owner;
        /// @dev Whitelisted flag for this operator
        bool whitelisted;
        /// @dev The state snapshot of the operator
        Snapshot snapshot;
    }

    /// @notice Represents a request to change an operator's fee
    struct OperatorFeeChangeRequest {
        /// @dev The new fee proposed by the operator
        uint64 fee;
        /// @dev The time when the approval period for the fee change begins
        uint64 approvalBeginTime;
        /// @dev The time when the approval period for the fee change ends
        uint64 approvalEndTime;
    }

    /// @notice Represents a cluster of validators
    struct Cluster {
        /// @dev The number of validators in the cluster
        uint32 validatorCount;
        /// @dev The index of network fees related to this cluster
        uint64 networkFeeIndex;
        /// @dev The last index calculated for the cluster
        uint64 index;
        /// @dev Flag indicating whether the cluster is active
        bool active;
        /// @dev The balance of the cluster
        uint256 balance;
    }

    /// @notice Registers a new validator on the SSV Network
    function registerValidator(
        bytes calldata publicKey,
        uint64[] memory operatorIds,
        bytes calldata sharesData,
        uint256 amount,
        Cluster memory cluster
    ) external;

    /// @notice Removes an existing validator from the SSV Network
    function removeValidator(bytes calldata publicKey, uint64[] memory operatorIds, Cluster memory cluster) external;

    /// @notice Reactivates a cluster
    function reactivate(uint64[] memory operatorIds, uint256 amount, Cluster memory cluster) external;

    /// @notice Deposits tokens into a cluster
    function deposit(address owner, uint64[] memory operatorIds, uint256 amount, Cluster memory cluster) external;

    /// @notice Withdraws tokens from a cluster
    function withdraw(uint64[] memory operatorIds, uint256 tokenAmount, Cluster memory cluster) external;

    /// @notice set ssv validator fee recipient address
    function setFeeRecipientAddress(address recipientAddress) external;

    /// @notice transfer ssv token
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice approve ssv token
    function approve(address spender, uint256 amount) external returns (bool);
}
