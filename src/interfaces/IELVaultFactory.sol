pragma solidity 0.8.8;

/**
 * @title Interface for ELVaultFactory
 * @notice Vault factory
 */

interface IELVaultFactory {
    /**
     * @notice create vault contract proxy
     * @param operatorId operator id
     */
    function create(uint256 operatorId) external returns (address);
}
