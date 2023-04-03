// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

/**
 * @title Interface for IVaultManager
 * @notice Vault will manage methods for rewards, commissions, tax
 */
interface IVaultManager {
    function settleAndReinvestElReward(uint256[] memory _operatorIds) external;
}