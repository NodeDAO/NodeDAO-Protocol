pragma solidity 0.8.8;

/**
 * @title Interface for LiquidStaking
 * @notice LiquidStaking
 */

interface ILiquidStaking {
    function receiveRewards(uint256 rewards) external payable;
}
