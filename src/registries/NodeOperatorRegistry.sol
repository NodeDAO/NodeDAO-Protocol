// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../interfaces/INodeOperatorsRegistry.sol";

/**
  * @title Node Operator registry
  *
  * Registration and management of Node Operator
  */
contract NodeOperatorRegistry is
    Initializable,
    OwnableUpgradeable,
    INodeOperatorsRegistry,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @dev Node Operator parameters
    struct NodeOperator {
        bool trusted;   // Trusted operator approved by dao
        address rewardAddress;  // Ethereum 1 address which receives steth rewards for this operator
        address controllerAddress; // Ethereum 1 address for the operator's management authority
        string name; // operator name, Human-readable name
    }

    /// @dev Mapping of all node operators. Mapping is used to be able to extend the struct.
    mapping(uint256 => NodeOperator) internal operators;

    // @dev Total number of operators
    uint256 internal totalOperators;

    // dao address
    address public dao;

    // dao treasury address
    address public daoValutAddress;
    // operator registration fee
    uint256 public registrationFee = 0.1 ether;

    event Transferred(address _to, uint256 _amount);

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    modifier validAddress(address _a) {
        require(_a != address(0), "EMPTY_ADDRESS");
        _;
    }

    modifier operatorExists(uint256 _id) {
        require(_id < totalOperators, "NODE_OPERATOR_NOT_FOUND");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(address _dao, address _daoValutAddress) public initializer {
        dao = _dao;
        dao = _daoValutAddress;
         __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    /**
    * @notice Add node operator named `name` with reward address `rewardAddress` and staking limit = 0 validators
    * @param _name Human-readable name
    * @param _rewardAddress Ethereum 1 address which receives ETH rewards for this operator
    * @param _controllerAddress Ethereum 1 address for the operator's management authority
    * @return id a unique key of the added operator
    */
    function registerOperator(string memory _name, address _rewardAddress, address _controllerAddress) external payable
        nonReentrant
        validAddress(_rewardAddress)
        validAddress(_controllerAddress)
        returns (uint256 id)
    {
        require(msg.value >= registrationFee, "Insufficient registration operator fee");

        id = totalOperators;

        totalOperators = id + 1;
        operators[id] = NodeOperator({
            trusted: false,
            rewardAddress: _rewardAddress,
            controllerAddress: _controllerAddress,
            name: _name
        });

        transfer(registrationFee, daoValutAddress);

        if (msg.value > registrationFee) {
            transfer(msg.value - registrationFee, daoValutAddress);
        }

        emit NodeOperatorRegistered(id, _name, _rewardAddress, _controllerAddress);
    }

    /**
      * @notice Set an operator as trusted
      * @param _id operator id
      */
    function setTrustedOperator(uint256 _id) external
        onlyDao
        operatorExists(_id)
    {
        NodeOperator memory operator = operators[_id];
        operators[_id].trusted = true;

        emit NodeOperatorTrustedSet(_id, operator.name, true);
    }

    /**
      * @notice Remove an operator as trusted
      * @param _id operator id
      */
    function removeTrustedOperator(uint256 _id) external
        onlyDao
        operatorExists(_id)
    {
        NodeOperator memory operator = operators[_id];
        operators[_id].trusted = false;

        emit NodeOperatorTrustedRemove(_id, operator.name, false);
    }

    /**
      * @notice Set the name of the operator
      * @param _id operator id
      * @param _name operator new name
      */
    function setNodeOperatorName(uint256 _id, string memory _name) external operatorExists(_id) {
        NodeOperator memory operator = operators[_id];
        require(msg.sender == operator.controllerAddress, "AUTH_FAILED");

        operators[_id].name = _name;
        emit NodeOperatorNameSet(_id, _name);
    }

    /**
      * @notice Set the rewardAddress of the operator
      * @param _id operator id
      * @param _rewardAddress Ethereum 1 address which receives ETH rewards for this operator
      */
    function setNodeOperatorRewardAddress(uint256 _id, address _rewardAddress) external operatorExists(_id) {
        NodeOperator memory operator = operators[_id];
        require(msg.sender == operator.controllerAddress, "AUTH_FAILED");

        operators[_id].rewardAddress = _rewardAddress;
        emit NodeOperatorRewardAddressSet(_id, operator.name, _rewardAddress);
    }

    /**
      * @notice Set the controllerAddress of the operator
      * @param _id operator id
      * @param _controllerAddress Ethereum 1 address for the operator's management authority
      */
    function setNodeOperatorControllerAddress(uint256 _id, address _controllerAddress) external operatorExists(_id) {
        NodeOperator memory operator = operators[_id];
        require(msg.sender == operator.controllerAddress, "AUTH_FAILED");

        operators[_id].rewardAddress = _controllerAddress;
        emit NodeOperatorControllerAddressSet(_id, operator.name, _controllerAddress);
    }

    /**
      * @notice Get information about an operator
      * @param _id operator id
      * @param _fullInfo Get all information
      */
    function getNodeOperator(uint256 _id, bool _fullInfo)external view
        operatorExists(_id)
        returns (
            bool trusted,
            string memory name,
            address rewardAddress,
            address controllerAddress
        )
    {
        NodeOperator memory operator = operators[_id];

        trusted = operator.trusted;
        name = _fullInfo ? operator.name : "";
        rewardAddress = operator.rewardAddress;
        controllerAddress = operator.controllerAddress;
    }

    /**
      * @notice Returns total number of node operators
      */
    function getNodeOperatorsCount() external view returns (uint256) {
        return totalOperators;
    }

   /**
      * @notice Returns whether an operator is trusted
      */
    function isTrusedOperator(uint256 _id) external view
        operatorExists(_id)
        returns (bool)
    {
        NodeOperator memory operator = operators[_id];
        return operator.trusted;
    }

   /**
      * @notice set dao valut address
      */
    function setDaoValutAddress(address _daoValutAddress) external onlyDao {
        daoValutAddress = _daoValutAddress;
    }

   /**
      * @notice set operator registration fee
      */
    function setRegistrationFee(uint256 _fee) external onlyDao {
        registrationFee = _fee;
    }

     function transfer(uint256 amount, address to) private {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }
}
