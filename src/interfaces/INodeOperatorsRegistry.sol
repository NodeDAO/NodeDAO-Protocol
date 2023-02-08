// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

/**
 * @title Node Operator registry
 *
 * Registration and management of Node Operator
 */
interface INodeOperatorsRegistry {
    /**
     * @notice Add node operator named `name` with reward address `rewardAddress` and staking limit = 0 validators
     * @param _name Human-readable name
     * @param _controllerAddress Ethereum 1 address for the operator's management authority
     * @return id a unique key of the added operator
     */
    function registerOperator(
        string memory _name,
        address _controllerAddress,
        address _owner,
        address[] memory _rewardAddresses,
        uint256[] memory _ratios
    ) external payable returns (uint256 id);

    /**
     * @notice Set an operator as trusted
     * @param _id operator id
     */
    function setTrustedOperator(uint256 _id) external;

    /**
     * @notice Remove an operator as trusted
     * @param _id operator id
     */
    function removeTrustedOperator(uint256 _id) external;

    /**
     * @notice Set the name of the operator
     * @param _id operator id
     * @param _name operator new name
     */
    function setNodeOperatorName(uint256 _id, string memory _name) external;

    /**
     * @notice Set the rewardAddress of the operator
     * @param _id operator id
     * @param _rewardAddresses Ethereum 1 address which receives ETH rewards for this operator
     */
    function setNodeOperatorRewardAddress(uint256 _id, address[] memory _rewardAddresses, uint256[] memory _ratios)
        external;

    /**
     * @notice Set the controllerAddress of the operator
     * @param _id operator id
     * @param _controllerAddress Ethereum 1 address for the operator's management authority
     */
    function setNodeOperatorControllerAddress(uint256 _id, address _controllerAddress) external;

    /**
     * @notice Get information about an operator
     * @param _id operator id
     * @param _fullInfo Get all information
     */
    function getNodeOperator(uint256 _id, bool _fullInfo)
        external
        view
        returns (
            bool trusted,
            string memory name,
            address owner,
            address controllerAddress,
            address vaultContractAddress
        );

    /**
     * @notice Get information about an operator vault contract address
     * @param _id operator id
     */
    function getNodeOperatorVaultContract(uint256 _id) external view returns (address vaultContractAddress);

    function getNodeOperatorRewardSetting(uint256 operatorId)
        external
        view
        returns (address[] memory, uint256[] memory);

    /**
     * @notice Returns total number of node operators
     */
    function getNodeOperatorsCount() external view returns (uint256);

    /**
     * @notice Returns total number of trusted operators
     */
    function getTrustedOperatorsCount() external view returns (uint256);

    /**
     * @notice Returns whether an operator is trusted
     */
    function isTrustedOperator(uint256 _id) external view returns (bool);

    /**
     * @notice Returns whether an operator is trusted
     */
    function isTrustedOperatorOfControllerAddress(address _controllerAddress) external view returns (uint256);

    function getPledgeBalanceOfOperator(uint256 operatorId) external view returns (uint256);

    function getNodeOperatorOwner(uint256 _id) external view returns (address);

    function slash(uint256 amount, uint256 operatorId) external;

    function deposit(uint256 amount, uint256 operatorId) external payable;

    function withdraw(uint256 amount, uint256 operatorId, address to) external;

    function isConformBasicPledge(uint256 operatorId) external view returns (bool);

    event NodeOperatorRegistered(
        uint256 id,
        string name,
        address controllerAddress,
        address _vaultContractAddress,
        address[] _rewardAddresses,
        uint256[] _ratios
    );
    event NodeOperatorTrustedSet(uint256 id, string name, bool trusted);
    event NodeOperatorTrustedRemove(uint256 id, string name, bool trusted);
    event NodeOperatorBlacklistSet(uint256 id);
    event NodeOperatorBlacklistRemove(uint256 id);
    event NodeOperatorNameSet(uint256 id, string name);
    event NodeOperatorRewardAddressSet(uint256 id, address[] _rewardAddresses, uint256[] _ratios);
    event NodeOperatorControllerAddressSet(uint256 id, string name, address controllerAddress);
    event NodeOperatorOwnerAddressSet(uint256 id, string name, address ownerAddress);
    event Transferred(address _to, uint256 _amount);
    event Slashed(uint256 _amount, uint256 _operatorId);
    event Deposited(uint256 _amount, uint256 _operatorId);
    event Withdraw(uint256 _amount, uint256 _operatorId, address _to);
    event LiquidStakingChanged(address _from, address _to);
    event PermissionlessBlockNumberSet(uint256 blockNumber);
}
