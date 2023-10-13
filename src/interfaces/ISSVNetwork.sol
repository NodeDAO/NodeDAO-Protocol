// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "./ISSVNetworkCore.sol";

interface ISSVNetwork is ISSVNetworkCore {
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
