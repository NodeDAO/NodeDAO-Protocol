// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

interface IBalanceOracle {
    /**
     * @return {uint256} The total balance of the consensus layer
     */
    function getClBalances() external view returns (uint256);

    /**
     * @return {uint256} The total balance of the pending validators
     */
    function getPendingBalances() external view returns (uint256);

    /**
     * @notice add pending validator value
     */
    function addPendingBalances(uint256 _pendingBalance) external;
}