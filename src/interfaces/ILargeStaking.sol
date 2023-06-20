pragma solidity 0.8.8;

/**
 * @title Interface for LargeStaking
 * @notice Vault factory
 */

interface ILargeStaking {
    function getOperatorValidatorCounts(uint256 _operatorId) external view returns (uint256);
}
