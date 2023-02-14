pragma solidity 0.8.8;

/**
 * @title Interface fro NodeDao LiquidStaking Contract
 *
 * NodeDao is a DAO that provides decentralized solutions for Ethereum liquidity,
 * jointly initiated by ChainUp Cloud, XHash, AntAlpha, ImToken, and Bitrise.
 *
 * The NodeDAO protocol is a smart contract for next-generation liquid staking derivatives,
 * which includes all the concepts of traditional liquid staking, re-staking, distributed validators, and validator NFTs in a single protocol.
 *
 * Our vision is to use our innovative liquidity solution to provide more options for the Ethereum liquidity market,
 * thereby making Ethereum staking more decentralized.
 */
interface ILiquidStaking {
    /**
     * @notice Register an operator to accept the user's stake
     * @param _name operator name
     * @param _controllerAddress operator contraller address
     * @param _owner This address is the operator owner and has the authority to change the control address and rewards address
     * @param _rewardAddresses Up to three addresses that accept operator rewards can be set
     * @param _ratios The allocation ratio corresponding to the rewards address by the operator
     */
    function registerOperator(
        string memory _name,
        address _controllerAddress,
        address _owner,
        address[] memory _rewardAddresses,
        uint256[] memory _ratios
    ) external payable returns (uint256);

    /**
     * @notice Receive Rewards
     * @param _rewards rewards amount
     */
    function receiveRewards(uint256 _rewards) external payable;

    /**
     * @notice Receive slash fund
     * @param _amount amount
     */
    function slashReceive(uint256 _amount) external payable;
}
