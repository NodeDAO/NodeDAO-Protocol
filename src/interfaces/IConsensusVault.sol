// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

/**
 * @title Interface for ConsensusVault
 * @notice Vault will manage methods for rewards, commissions, tax
 */
interface IConsensusVault {
    function transfer(uint256 _amount, address _to) external;
    function reinvestment(uint256 _amount) external;
}
