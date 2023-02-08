pragma solidity 0.8.8;

/**
 * @title Interface for LiquidStaking
 * @notice LiquidStaking
 */

interface ILiquidStaking {
    function registerOperator(
        string memory _name,
        address _controllerAddress,
        address _owner,
        address[] memory _rewardAddresses,
        uint256[] memory _ratios
    ) external payable returns (uint256);

    function receiveRewards(uint256 rewards) external payable;

    function slashReceive(uint256 amount) external payable;
}
