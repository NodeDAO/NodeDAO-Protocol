// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/IELVaultFactory.sol";
import "src/interfaces/ILiquidStaking.sol";

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
    struct RewardSetting {
        address rewardAddress;
        uint256 ratio;
    }

    /// @dev Node Operator parameters
    struct NodeOperator {
        bool trusted; // Trusted operator approved by dao
        address owner;
        address controllerAddress; // Ethereum 1 address for the operator's management authority
        address vaultContractAddress; // Ethereum 1 contract address for the operator's vault
        string name; // operator name, Human-readable name
    }

    /// @dev Mapping of all node operators. Mapping is used to be able to extend the struct.
    mapping(uint256 => NodeOperator) internal operators;

    uint256 internal constant MAX_REWARDSETTING_LENGTH = 3;
    mapping(uint256 => RewardSetting[]) internal operatorRewardSetting;

    mapping(address => uint256) public trustedControllerAddress;
    mapping(address => uint256) public controllerAddress;
    mapping(address => bool) public usedControllerAddress;

    mapping(uint256 => bool) public blacklistOperators;

    // @dev Total number of operators
    uint256 internal totalOperators;
    uint256 internal totalTrustedOperators;
    uint256 internal totalBlacklistOperators;

    // dao address
    address public dao;

    // dao treasury address
    address public daoVaultAddress;
    // operator registration fee
    uint256 public registrationFee;

    uint256 public permissionlessBlockNumber;

    uint256 public constant BASIC_PLEDGE = 1 ether;
    mapping(uint256 => uint256) public operatorPledgeVaultBalances;

    IELVaultFactory public vaultFactoryContract;
    ILiquidStaking public liquidStakingContract;

    modifier onlyLiquidStaking() {
        require(address(liquidStakingContract) == msg.sender, "PERMISSION_DENIED");
        _;
    }

    modifier onlyDao() {
        require(msg.sender == dao, "PERMISSION_DENIED");
        _;
    }

    modifier validAddress(address _a) {
        require(_a != address(0), "EMPTY_ADDRESS");
        _;
    }

    modifier operatorExists(uint256 _id) {
        require(_id != 0 && _id <= totalOperators, "NODE_OPERATOR_NOT_FOUND");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(address _dao, address _daoVaultAddress, address _vaultFactoryContractAddress)
        public
        initializer
    {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        daoVaultAddress = _daoVaultAddress;
        vaultFactoryContract = IELVaultFactory(_vaultFactoryContractAddress);
        registrationFee = 0.1 ether;
        permissionlessBlockNumber = 0;
    }

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
    )
        external
        payable
        nonReentrant
        validAddress(_controllerAddress)
        validAddress(_owner)
        onlyLiquidStaking
        returns (uint256 id)
    {
        require(msg.value == BASIC_PLEDGE + registrationFee, "Invalid registration operator fee");
        require(!usedControllerAddress[_controllerAddress], "controllerAddress is used");
        id = totalOperators + 1;

        totalOperators = id;

        address vaultContractAddress = vaultFactoryContract.create(id);

        operators[id] = NodeOperator({
            trusted: false,
            owner: _owner,
            controllerAddress: _controllerAddress,
            vaultContractAddress: vaultContractAddress,
            name: _name
        });

        _setNodeOperatorRewardAddress(id, _rewardAddresses, _ratios);

        usedControllerAddress[_controllerAddress] = true;
        controllerAddress[_controllerAddress] = id;

        operatorPledgeVaultBalances[id] += BASIC_PLEDGE;
        emit Deposited(BASIC_PLEDGE, id);

        transfer(registrationFee, daoVaultAddress);

        emit NodeOperatorRegistered(id, _name, _controllerAddress, vaultContractAddress, _rewardAddresses, _ratios);
    }

    /**
     * @notice Set an operator as trusted
     * @param _id operator id
     */
    function setTrustedOperator(uint256 _id) external onlyDao operatorExists(_id) {
        _checkPermission();

        NodeOperator memory operator = operators[_id];
        require(!operator.trusted, "The operator is already trusted");
        operators[_id].trusted = true;
        totalTrustedOperators += 1;
        trustedControllerAddress[operator.controllerAddress] = _id;
        emit NodeOperatorTrustedSet(_id, operator.name, true);
    }

    /**
     * @notice Remove an operator as trusted
     * @param _id operator id
     */
    function removeTrustedOperator(uint256 _id) external onlyDao operatorExists(_id) {
        _checkPermission();

        NodeOperator memory operator = operators[_id];
        require(operator.trusted, "operator is not trusted");
        operators[_id].trusted = false;
        totalTrustedOperators -= 1;
        trustedControllerAddress[operator.controllerAddress] = 0;
        emit NodeOperatorTrustedRemove(_id, operator.name, false);
    }

    function setBlacklistOperator(uint256 _id) external onlyDao operatorExists(_id) {
        require(!blacklistOperators[_id], "This operator has been blacklisted");
        blacklistOperators[_id] = true;
        totalBlacklistOperators += 1;
        emit NodeOperatorBlacklistSet(_id);
    }

    /**
     * @notice Remove an operator as blacklist
     * @param _id operator id
     */
    function removeBlacklistOperator(uint256 _id) external onlyDao operatorExists(_id) {
        require(blacklistOperators[_id], "The operator is not blacklisted");
        blacklistOperators[_id] = false;
        totalBlacklistOperators -= 1;
        emit NodeOperatorBlacklistRemove(_id);
    }

    function _checkPermission() internal {
        if (permissionlessBlockNumber != 0) {
            require(block.number < permissionlessBlockNumber, "No permission phase");
        }
    }

    /**
     * @notice Set the name of the operator
     * @param _id operator id
     * @param _name operator new name
     */
    function setNodeOperatorName(uint256 _id, string memory _name) external operatorExists(_id) {
        NodeOperator memory operator = operators[_id];
        require(msg.sender == operator.owner, "PERMISSION_DENIED");

        operators[_id].name = _name;
        emit NodeOperatorNameSet(_id, _name);
    }

    /**
     * @notice Set the rewardAddress of the operator
     * @param _id operator id
     * @param _rewardAddresses Ethereum 1 address which receives ETH rewards for this operator
     */
    function setNodeOperatorRewardAddress(uint256 _id, address[] memory _rewardAddresses, uint256[] memory _ratios)
        external
        operatorExists(_id)
    {
        NodeOperator memory operator = operators[_id];
        require(msg.sender == operator.owner, "PERMISSION_DENIED");

        _setNodeOperatorRewardAddress(_id, _rewardAddresses, _ratios);
        emit NodeOperatorRewardAddressSet(_id, _rewardAddresses, _ratios);
    }

    function _setNodeOperatorRewardAddress(uint256 _id, address[] memory _rewardAddresses, uint256[] memory _ratios)
        internal
    {
        require(_rewardAddresses.length != 0, "Invalid length");
        require(_rewardAddresses.length <= MAX_REWARDSETTING_LENGTH, "Invalid length");
        require(_rewardAddresses.length == _ratios.length, "Invalid length");

        delete operatorRewardSetting[_id];

        uint256 totalRatio = 0;
        for (uint256 i = 0; i < _rewardAddresses.length; i++) {
            require(_rewardAddresses[i] != address(0), "EMPTY_ADDRESS");
            operatorRewardSetting[_id].push(RewardSetting({rewardAddress: _rewardAddresses[i], ratio: _ratios[i]}));

            totalRatio += _ratios[i];
        }
        require(totalRatio == 100, "Invalid Ratio");
    }

    /**
     * @notice Set the controllerAddress of the operator
     * @param _id operator id
     * @param _controllerAddress Ethereum 1 address for the operator's management authority
     */
    function setNodeOperatorControllerAddress(uint256 _id, address _controllerAddress) external operatorExists(_id) {
        require(!usedControllerAddress[_controllerAddress], "controllerAddress is used");

        NodeOperator memory operator = operators[_id];
        require(msg.sender == operator.owner, "PERMISSION_DENIED");
        if (trustedControllerAddress[operator.controllerAddress] == _id) {
            trustedControllerAddress[operator.controllerAddress] = 0;
            trustedControllerAddress[_controllerAddress] = _id;
        }

        controllerAddress[operator.controllerAddress] = 0;
        controllerAddress[_controllerAddress] = _id;
        operators[_id].controllerAddress = _controllerAddress;
        usedControllerAddress[_controllerAddress] = true;

        emit NodeOperatorControllerAddressSet(_id, operator.name, _controllerAddress);
    }

    function setNodeOperatorOwnerAddress(uint256 _id, address _owner) external operatorExists(_id) {
        NodeOperator memory operator = operators[_id];
        require(msg.sender == operator.owner || msg.sender == dao, "PERMISSION_DENIED");

        operators[_id].owner = _owner;

        emit NodeOperatorOwnerAddressSet(_id, operator.name, _owner);
    }

    /**
     * @notice Get information about an operator
     * @param _id operator id
     * @param _fullInfo Get all information
     */
    function getNodeOperator(uint256 _id, bool _fullInfo)
        external
        view
        operatorExists(_id)
        returns (
            bool trusted,
            string memory name,
            address owner,
            address controllerAddress,
            address vaultContractAddress
        )
    {
        NodeOperator memory operator = operators[_id];

        trusted = operator.trusted;
        name = _fullInfo ? operator.name : "";
        owner = operator.owner;
        controllerAddress = operator.controllerAddress;
        vaultContractAddress = operator.vaultContractAddress;
    }

    /**
     * @notice Get information about an operator vault contract address
     * @param _id operator id
     */
    function getNodeOperatorVaultContract(uint256 _id)
        external
        view
        operatorExists(_id)
        returns (address vaultContractAddress)
    {
        NodeOperator memory operator = operators[_id];
        vaultContractAddress = operator.vaultContractAddress;
    }

    function getNodeOperatorOwner(uint256 _id) external view operatorExists(_id) returns (address owner) {
        NodeOperator memory operator = operators[_id];
        owner = operator.owner;
    }

    function getNodeOperatorRewardSetting(uint256 operatorId)
        external
        view
        returns (address[] memory rewardAddresses, uint256[] memory ratios)
    {
        RewardSetting[] memory rewardSetting = operatorRewardSetting[operatorId];
        rewardAddresses = new address[] (rewardSetting.length);
        ratios = new uint256[] (rewardSetting.length);
        for (uint256 i = 0; i < rewardSetting.length; i++) {
            rewardAddresses[i] = rewardSetting[i].rewardAddress;
            ratios[i] = rewardSetting[i].ratio;
        }

        return (rewardAddresses, ratios);
    }

    /**
     * @notice Returns total number of node operators
     */
    function getNodeOperatorsCount() external view returns (uint256) {
        return totalOperators;
    }

    /**
     * @notice Returns total number of trusted operators
     */
    function getTrustedOperatorsCount() external view returns (uint256) {
        if (permissionlessBlockNumber != 0 && block.number >= permissionlessBlockNumber) {
            return totalOperators;
        }

        return totalTrustedOperators;
    }

    /**
     * @notice Returns whether an operator is trusted
     */
    function isTrustedOperator(uint256 _id) external view operatorExists(_id) returns (bool) {
        if (blacklistOperators[_id]) {
            return false;
        }

        if (permissionlessBlockNumber != 0 && block.number >= permissionlessBlockNumber) {
            return true;
        }

        NodeOperator memory operator = operators[_id];
        return operator.trusted;
    }

    /**
     * @notice Returns whether an operator is trusted
     */
    function isTrustedOperatorOfControllerAddress(address _controllerAddress) external view returns (uint256) {
        uint256 _id = controllerAddress[_controllerAddress];
        if (blacklistOperators[_id]) {
            return 0;
        }

        if (permissionlessBlockNumber != 0 && block.number >= permissionlessBlockNumber) {
            return _id;
        }

        return trustedControllerAddress[_controllerAddress];
    }

    function deposit(uint256 amount, uint256 operatorId) external payable nonReentrant {
        operatorPledgeVaultBalances[operatorId] += amount;
        emit Deposited(amount, operatorId);
    }

    function withdraw(uint256 amount, uint256 operatorId, address to) external nonReentrant onlyLiquidStaking {
        require(to != address(0), "Recipient address provided invalid");
        require(amount > registrationFee, "");
        require(operatorPledgeVaultBalances[operatorId] >= amount, "Insufficient funds");
        operatorPledgeVaultBalances[operatorId] -= amount;
        payable(to).transfer(amount);

        emit Withdraw(amount, operatorId, to);
    }

    function slash(uint256 amount, uint256 operatorId) external nonReentrant onlyLiquidStaking {
        require(operatorPledgeVaultBalances[operatorId] >= amount, "Insufficient funds");
        operatorPledgeVaultBalances[operatorId] -= amount;
        liquidStakingContract.slashReceive{value: amount}(amount);
        emit Slashed(amount, operatorId);
    }

    function getPledgeBalanceOfOperator(uint256 operatorId) external view returns (uint256) {
        return operatorPledgeVaultBalances[operatorId];
    }

    function isConformBasicPledge(uint256 operatorId) external view returns (bool) {
        return operatorPledgeVaultBalances[operatorId] >= BASIC_PLEDGE;
    }

    /**
     * @notice Set proxy address of LiquidStaking
     * @param liquidStakingProxyAddress_ proxy address of LiquidStaking
     * @dev will only allow call of function by the address registered as the owner
     */
    function setLiquidStaking(address liquidStakingProxyAddress_) external onlyDao {
        require(liquidStakingProxyAddress_ != address(0), "Aggregator address provided invalid");
        emit LiquidStakingChanged(address(liquidStakingContract), liquidStakingProxyAddress_);
        liquidStakingContract = ILiquidStaking(liquidStakingProxyAddress_);
    }

    /**
     * @notice set dao vault address
     */
    function setDaoAddress(address _dao) external onlyDao {
        dao = _dao;
    }

    /**
     * @notice set dao vault address
     */
    function setDaoVaultAddress(address _daoVaultAddress) external onlyDao {
        daoVaultAddress = _daoVaultAddress;
    }

    /**
     * @notice set operator registration fee
     */
    function setRegistrationFee(uint256 _fee) external onlyDao {
        registrationFee = _fee;
    }

    function setpermissionlessBlockNumber(uint256 blockNumber) external onlyDao {
        require(permissionlessBlockNumber == 0, "The permissionless phase has begun");
        require(blockNumber > block.number, "Invalid block height");
        permissionlessBlockNumber = blockNumber;
        emit PermissionlessBlockNumberSet(blockNumber);
    }
    /**
     * @notice transfer amount to an address
     */

    function transfer(uint256 amount, address to) internal {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }
}
