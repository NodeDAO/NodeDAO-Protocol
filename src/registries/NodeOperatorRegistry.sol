// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts/utils/math/Math.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/IELVaultFactory.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/IELVault.sol";
import "src/interfaces/IOperatorSlash.sol";
import "src/interfaces/ILargeStaking.sol";

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
    using Math for uint256;

    struct RewardSetting {
        address rewardAddress;
        uint256 ratio;
    }

    /// @dev Node Operator parameters
    struct NodeOperator {
        bool trusted; // Trusted operator approved by dao
        bool isQuit;
        address owner;
        address controllerAddress; // Ethereum 1 address for the operator's management authority
        address vaultContractAddress; // Ethereum 1 contract address for the operator's vault
        string name; // operator name, Human-readable name
    }

    IELVaultFactory public vaultFactoryContract;

    ILiquidStaking public liquidStakingContract;

    IVNFT public vNFTContract;

    /// @dev Mapping of all node operators. Mapping is used to be able to extend the struct.
    mapping(uint256 => NodeOperator) internal operators;

    uint256 internal constant MAX_REWARDSETTING_LENGTH = 3;
    // operator reward settings
    mapping(uint256 => RewardSetting[]) internal operatorRewardSetting;

    // trusted operator set
    mapping(address => uint256) public trustedControllerAddress;
    // The operator corresponding to the control address
    mapping(address => uint256) public controllerAddress;
    // The used control address, an address can only be used once
    mapping(address => bool) public usedControllerAddress;
    // blacklist operator set
    mapping(uint256 => bool) public blacklistOperators;

    // Total number of operators
    uint256 internal totalOperators;
    uint256 internal totalTrustedOperators;
    uint256 internal totalBlacklistOperators;

    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;

    // operator registration fee
    uint256 public registrationFee;

    // The block height at the start of the permissionless phase
    uint256 public permissionlessBlockNumber;

    uint256 public constant BASIC_PLEDGE = 1 ether;
    // operator pledge funds set
    mapping(uint256 => uint256) public operatorPledgeVaultBalances;

    // v2 storage
    IOperatorSlash public operatorSlashContract;

    mapping(uint256 => uint256) public operatorSlashAmountOwed;
    mapping(uint256 => uint256) internal operatorCommissionRate;
    uint256 public defaultOperatorCommission;

    // v3 storage
    ILargeStaking public largeStakingContract;

    error PermissionDenied();
    error InvalidAddr();
    error InvalidParameter();
    error OperatorNotFound();
    error InvalidCommission();
    error InsufficientAmount();
    error ControllerAddrUsed();
    error OperatorHasArrears();
    error OperatorHasBlacklisted();
    error InsufficientMargin();
    error OperatorHasExited();
    error OperatorExitFailed();
    error OperatorAlreadyTrusted();
    error OperatorNotTrusted();
    error OperatorNotBlacklisted();
    error NoPermissionPhase();
    error InvalidRewardRatio();
    error PermissionlessPhaseStart();

    modifier onlyOperatorSlash() {
        if (msg.sender != address(operatorSlashContract)) revert PermissionDenied();
        _;
    }

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    modifier validAddress(address _a) {
        if (_a == address(0)) revert InvalidParameter();
        _;
    }

    modifier operatorExists(uint256 _id) {
        if (_id == 0 || _id > totalOperators) revert OperatorNotFound();
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    /**
     * @notice initialize NodeOperatorRegistry Contract
     * @param _dao Dao contract address
     * @param _daoVaultAddress Dao Vault Address
     * @param _vaultFactoryContractAddress vault factory contract address
     */
    function initialize(
        address _dao,
        address _daoVaultAddress,
        address _vaultFactoryContractAddress,
        address _nVNFTContractAddress
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        daoVaultAddress = _daoVaultAddress;
        vaultFactoryContract = IELVaultFactory(_vaultFactoryContractAddress);
        vNFTContract = IVNFT(_nVNFTContractAddress);
        registrationFee = 0.1 ether;
        permissionlessBlockNumber = 0;
    }

    /**
     * @notice initializeV2 NodeOperatorRegistry Contract
     * @param _vaultFactoryContractAddress new vault factory contract address
     * @param _resetVaultOperatorIds reset vault contract
     */
    function initializeV2(
        address _vaultFactoryContractAddress,
        address _operatorSlashContractAddress,
        uint256[] memory _resetVaultOperatorIds
    ) public reinitializer(2) onlyDao {
        defaultOperatorCommission = 2000;
        emit VaultFactorContractSet(address(vaultFactoryContract), _vaultFactoryContractAddress);
        vaultFactoryContract = IELVaultFactory(_vaultFactoryContractAddress);

        emit OperatorSlashContractSet(address(operatorSlashContract), _operatorSlashContractAddress);
        operatorSlashContract = IOperatorSlash(_operatorSlashContractAddress);
        for (uint256 i = 0; i < _resetVaultOperatorIds.length; ++i) {
            _resetOperatorVaultContract(_resetVaultOperatorIds[i]);
        }
    }

    function initializeV3(address _largeStakingContractAddress) public reinitializer(3) onlyOwner {
        largeStakingContract = ILargeStaking(_largeStakingContractAddress);
    }

    /**
     * @notice Add node operator named `name` with reward address `rewardAddress` and _owner
     * @param _name Human-readable name
     * @param _controllerAddress Ethereum 1 address for the operator's management authority
     * @param _owner operator owner address
     * @param _rewardAddresses reward addresses
     * @param _ratios reward ratios
     * @return id a unique key of the added operator
     */

    function registerOperator(
        string calldata _name,
        address _controllerAddress,
        address _owner,
        address[] calldata _rewardAddresses,
        uint256[] calldata _ratios
    ) external payable nonReentrant validAddress(_controllerAddress) validAddress(_owner) returns (uint256 id) {
        if (bytes(_name).length > 32) revert InvalidParameter();
        if (msg.value < BASIC_PLEDGE + registrationFee) revert InsufficientAmount();
        if (usedControllerAddress[_controllerAddress]) revert ControllerAddrUsed();
        id = totalOperators + 1;

        totalOperators = id;

        // Generate a vault contract for the operator
        address vaultContractAddress = vaultFactoryContract.create(id);

        operators[id] = NodeOperator({
            trusted: false,
            isQuit: false,
            owner: _owner,
            controllerAddress: _controllerAddress,
            vaultContractAddress: vaultContractAddress,
            name: _name
        });

        _setNodeOperatorRewardAddress(id, _rewardAddresses, _ratios);

        usedControllerAddress[_controllerAddress] = true;
        controllerAddress[_controllerAddress] = id;

        uint256 pledgeAmount = msg.value - registrationFee;
        operatorPledgeVaultBalances[id] += pledgeAmount;
        emit PledgeDeposited(pledgeAmount, id);

        if (registrationFee > 0) {
            transfer(registrationFee, daoVaultAddress);
        }

        emit NodeOperatorRegistered(id, _name, _controllerAddress, vaultContractAddress, _rewardAddresses, _ratios);
    }

    /**
     * @notice Withdraw the deposit available to the operator, it must be sent by the operator owner
     * @param _operatorId operator id
     * @param _withdrawAmount withdrawal amount
     * @param _to receiving address
     */

    function withdrawOperator(uint256 _operatorId, uint256 _withdrawAmount, address _to) external nonReentrant {
        if (blacklistOperators[_operatorId]) revert OperatorHasBlacklisted();
        if (operatorSlashAmountOwed[_operatorId] != 0) revert OperatorHasArrears();
        if (_to == address(0)) revert InvalidAddr();

        NodeOperator memory operator = operators[_operatorId];
        if (operator.owner != msg.sender) revert PermissionDenied();

        uint256 requireVault = calcRequirePledgeBalance(_operatorId);

        // After the withdrawal is completed, the pledge funds requirements must also be met
        if (operatorPledgeVaultBalances[_operatorId] < requireVault + _withdrawAmount) revert InsufficientMargin();
        operatorPledgeVaultBalances[_operatorId] -= _withdrawAmount;
        payable(_to).transfer(_withdrawAmount);

        emit OperatorWithdraw(_operatorId, _withdrawAmount, _to);
    }

    function calcRequirePledgeBalance(uint256 _operatorId) internal view returns (uint256) {
        uint256 operatorNftCounts = vNFTContract.getActiveNftCountsOfOperator(_operatorId)
            + vNFTContract.getEmptyNftCountsOfOperator(_operatorId)
            + largeStakingContract.getOperatorValidatorCounts(_operatorId);
        // Pledge the required funds based on the number of validators
        uint256 requireVault = 0;
        if (operatorNftCounts <= 100) {
            requireVault = (operatorNftCounts * 10 / 100) * 1 ether;
            if (requireVault < 1 ether) {
                requireVault = 1 ether;
            }
        } else {
            requireVault = operatorNftCounts.sqrt() * 1 ether;
        }

        return requireVault;
    }

    /**
     * @notice Exit the operator. When there are no validators running, the owner of the operator has the right to opt out.
     * Unused funds must be transferred to another active operator
     * @param _operatorId operator id
     * @param _to The receiving address of the pledged funds of the withdrawn operator
     */
    function quitOperator(uint256 _operatorId, address _to) external {
        if (blacklistOperators[_operatorId]) revert OperatorHasBlacklisted();
        if (operatorSlashAmountOwed[_operatorId] != 0) revert OperatorHasArrears();
        NodeOperator memory operator = operators[_operatorId];
        if (operator.owner != msg.sender) revert PermissionDenied();
        if (operators[_operatorId].isQuit) revert OperatorHasExited();

        uint256 operatorNftCounts = vNFTContract.getActiveNftCountsOfOperator(_operatorId)
            + vNFTContract.getEmptyNftCountsOfOperator(_operatorId);
        // There are active validators and cannot exit
        if (operatorNftCounts != 0) revert OperatorExitFailed();

        uint256 nowPledge = operatorPledgeVaultBalances[_operatorId];
        operatorPledgeVaultBalances[_operatorId] = 0;

        if (_to == address(0)) revert InvalidAddr();
        payable(_to).transfer(nowPledge);
        operators[_operatorId].isQuit = true;

        emit OperatorQuit(_operatorId, nowPledge, _to);
    }

    /**
     * @notice Set an operator as trusted
     * @param _id operator id
     */

    function setTrustedOperator(uint256 _id) external onlyDao operatorExists(_id) {
        _checkPermission();

        NodeOperator memory operator = operators[_id];
        if (operator.trusted) revert OperatorAlreadyTrusted();
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
        if (!operator.trusted) revert OperatorNotTrusted();
        operators[_id].trusted = false;
        totalTrustedOperators -= 1;
        trustedControllerAddress[operator.controllerAddress] = 0;
        emit NodeOperatorTrustedRemove(_id, operator.name, false);
    }

    /**
     * @notice Set an operator as blacklist
     * @param _id operator id
     */
    function setBlacklistOperator(uint256 _id) external onlyDao operatorExists(_id) {
        if (blacklistOperators[_id]) revert OperatorHasBlacklisted();
        blacklistOperators[_id] = true;
        totalBlacklistOperators += 1;
        emit NodeOperatorBlacklistSet(_id);
    }

    /**
     * @notice Remove an operator as blacklist
     * @param _id operator id
     */

    function removeBlacklistOperator(uint256 _id) external onlyDao operatorExists(_id) {
        if (!blacklistOperators[_id]) revert OperatorNotBlacklisted();
        blacklistOperators[_id] = false;
        totalBlacklistOperators -= 1;
        emit NodeOperatorBlacklistRemove(_id);
    }

    function _checkPermission() internal view {
        if (permissionlessBlockNumber != 0) {
            if (block.number >= permissionlessBlockNumber) revert NoPermissionPhase();
        }
    }

    function _setNodeOperatorRewardAddress(uint256 _id, address[] calldata _rewardAddresses, uint256[] calldata _ratios)
        internal
    {
        if (
            _rewardAddresses.length == 0 || _rewardAddresses.length > MAX_REWARDSETTING_LENGTH
                || _rewardAddresses.length != _ratios.length
        ) revert InvalidParameter();

        // clear old settings
        delete operatorRewardSetting[_id];

        uint256 totalRatio = 0;
        for (uint256 i = 0; i < _rewardAddresses.length; ++i) {
            if (_rewardAddresses[i] == address(0)) revert InvalidAddr();
            operatorRewardSetting[_id].push(RewardSetting({rewardAddress: _rewardAddresses[i], ratio: _ratios[i]}));

            totalRatio += _ratios[i];
        }

        // Ratio sum should be 100%
        if (totalRatio != 100) revert InvalidRewardRatio();
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
            bool _trusted,
            string memory _name,
            address _owner,
            address _controllerAddress,
            address _vaultContractAddress
        )
    {
        NodeOperator memory operator = operators[_id];

        _trusted = operator.trusted;
        _name = _fullInfo ? operator.name : "";
        _owner = operator.owner;
        _controllerAddress = operator.controllerAddress;
        _vaultContractAddress = operator.vaultContractAddress;
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
        return operators[_id].vaultContractAddress;
    }

    /**
     * @notice Get operator rewardSetting
     * @param _operatorId operator id
     */
    function getNodeOperatorRewardSetting(uint256 _operatorId)
        external
        view
        returns (address[] memory rewardAddresses, uint256[] memory ratios)
    {
        RewardSetting[] memory rewardSetting = operatorRewardSetting[_operatorId];
        rewardAddresses = new address[] (rewardSetting.length);
        ratios = new uint256[] (rewardSetting.length);
        for (uint256 i = 0; i < rewardSetting.length; ++i) {
            rewardAddresses[i] = rewardSetting[i].rewardAddress;
            ratios[i] = rewardSetting[i].ratio;
        }

        return (rewardAddresses, ratios);
    }

    /**
     * @notice Returns whether an operator is trusted
     * @param _operatorId operator id
     */
    function isTrustedOperator(uint256 _operatorId) external view operatorExists(_operatorId) returns (bool) {
        if (blacklistOperators[_operatorId]) {
            return false;
        }

        if (operators[_operatorId].isQuit) {
            return false;
        }

        if (permissionlessBlockNumber != 0 && block.number >= permissionlessBlockNumber) {
            return true;
        }

        return operators[_operatorId].trusted;
    }

    /**
     * @notice Returns whether an operator is quit
     * @param _operatorId operator id
     */
    function isQuitOperator(uint256 _operatorId) external view operatorExists(_operatorId) returns (bool) {
        return operators[_operatorId].isQuit;
    }

    /**
     * @notice Returns whether an operator is Blacklist
     * @param _operatorId operator id
     */
    function isBlacklistOperator(uint256 _operatorId) external view operatorExists(_operatorId) returns (bool) {
        if (blacklistOperators[_operatorId]) {
            return true;
        }

        return false;
    }

    /**
     * @notice Returns whether an operator is trusted， return operatorId
     * @param _controllerAddress controller address
     */
    function isTrustedOperatorOfControllerAddress(address _controllerAddress) external view returns (uint256) {
        uint256 _id = controllerAddress[_controllerAddress];
        if (blacklistOperators[_id]) {
            return 0;
        }

        if (operators[_id].isQuit) {
            return 0;
        }

        if (permissionlessBlockNumber != 0 && block.number >= permissionlessBlockNumber) {
            return _id;
        }

        return trustedControllerAddress[_controllerAddress];
    }

    /**
     * @notice deposit pledge fund for operator
     * @param _operatorId operator Id
     */
    function deposit(uint256 _operatorId) external payable nonReentrant {
        if (operators[_operatorId].isQuit) revert OperatorHasExited();

        uint256 amountOwed = operatorSlashAmountOwed[_operatorId];
        if (amountOwed > 0) {
            if (amountOwed > msg.value) {
                operatorSlashContract.slashArrearsReceive{value: msg.value}(_operatorId, msg.value);
                operatorSlashAmountOwed[_operatorId] -= msg.value;
                emit OperatorArrearsReduce(_operatorId, msg.value);
            } else {
                operatorSlashContract.slashArrearsReceive{value: amountOwed}(_operatorId, amountOwed);
                operatorSlashAmountOwed[_operatorId] = 0;
                operatorPledgeVaultBalances[_operatorId] += msg.value - amountOwed;
                emit OperatorArrearsReduce(_operatorId, amountOwed);
            }
        } else {
            operatorPledgeVaultBalances[_operatorId] += msg.value;
        }

        emit PledgeDeposited(msg.value, _operatorId);
    }

    function _slash(uint256 _operatorId, uint256 _amount) internal operatorExists(_operatorId) returns (uint256) {
        uint256 pledgeAmounts = operatorPledgeVaultBalances[_operatorId];
        if (pledgeAmounts == 0) {
            emit OperatorArrearsIncrease(_operatorId, _amount);
            operatorSlashAmountOwed[_operatorId] += _amount;
            return 0;
        }

        if (pledgeAmounts >= _amount) {
            operatorPledgeVaultBalances[_operatorId] -= _amount;
            emit Slashed(_operatorId, _amount);
            return _amount;
        } else {
            uint256 slashAmountAdded = _amount - pledgeAmounts;
            operatorSlashAmountOwed[_operatorId] += slashAmountAdded;
            emit OperatorArrearsIncrease(_operatorId, slashAmountAdded);
            operatorPledgeVaultBalances[_operatorId] = 0;
            emit Slashed(_operatorId, pledgeAmounts);
            return pledgeAmounts;
        }
    }

    /**
     * @notice When a validator run by an operator goes seriously offline, it will be slashed
     * @param _slashType slashType
     * @param _slashIds tokenId or stakingId
     * @param _operatorIds operator id
     * @param _amounts slash amount
     */
    function slash(
        uint256 _slashType,
        uint256[] memory _slashIds,
        uint256[] memory _operatorIds,
        uint256[] memory _amounts
    ) external nonReentrant onlyOperatorSlash {
        uint256 totalSlashAmounts = 0;
        uint256[] memory slashAmounts = new uint256[] (_operatorIds.length);
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 amount = _amounts[i];
            if (amount == 0) {
                continue;
            }

            uint256 operatorId = _operatorIds[i];
            uint256 slashAmount = _slash(operatorId, amount);
            slashAmounts[i] = slashAmount;
            totalSlashAmounts += slashAmount;
        }

        operatorSlashContract.slashReceive{value: totalSlashAmounts}(
            _slashType, _slashIds, _operatorIds, slashAmounts, _amounts
        );
    }

    /**
     * @notice Determine whether the operator meets the pledge requirements
     * @param _operatorId operator id
     */
    function isConformBasicPledge(uint256 _operatorId) external view returns (bool) {
        return operatorPledgeVaultBalances[_operatorId] >= BASIC_PLEDGE;
    }

    /**
     * @notice operator pledge balance
     * @param _operatorId operator id
     */
    function getPledgeInfoOfOperator(uint256 _operatorId) external view returns (uint256, uint256) {
        uint256 requireBalance = calcRequirePledgeBalance(_operatorId);
        return (operatorPledgeVaultBalances[_operatorId], requireBalance);
    }

    /**
     * @notice reset a new vault contract for operator
     * @param _operatorIds operators id
     */
    function resetOperatorVaultContract(uint256[] calldata _operatorIds) external onlyDao {
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 operatorId = _operatorIds[i];
            _resetOperatorVaultContract(operatorId);
        }
    }

    function _resetOperatorVaultContract(uint256 _operatorId) internal {
        address vaultContractAddress = vaultFactoryContract.create(_operatorId);
        emit OperatorVaultContractReset(operators[_operatorId].vaultContractAddress, vaultContractAddress);
        operators[_operatorId].vaultContractAddress = vaultContractAddress;
    }

    /**
     * @notice get operator commission rate
     * @param _operatorIds operator id
     */
    function getOperatorCommissionRate(uint256[] memory _operatorIds) external view returns (uint256[] memory) {
        uint256[] memory commissions = new uint256[] (_operatorIds.length);
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            if (operatorCommissionRate[_operatorIds[i]] == 0) {
                commissions[i] = defaultOperatorCommission;
            } else {
                commissions[i] = operatorCommissionRate[_operatorIds[i]];
            }
        }

        return commissions;
    }

    /**
     * @notice set operator comission rate
     * @param _operatorId operator id
     * @param _rate _rate
     */
    function setOperatorCommissionRate(uint256 _operatorId, uint256 _rate) external onlyDao {
        if (_rate >= 5000) revert InvalidCommission();
        uint256 commissionRate = operatorCommissionRate[_operatorId];
        emit CommissionRateChanged(commissionRate == 0 ? defaultOperatorCommission : commissionRate, _rate);
        operatorCommissionRate[_operatorId] = _rate;
    }

    /**
     * @notice Change the owner of the operator
     * @param _id operator id
     * @param _owner Ethereum 1 address for the operator's owner authority
     */
    function setNodeOperatorOwnerAddress(uint256 _id, address _owner) external operatorExists(_id) {
        NodeOperator memory operator = operators[_id];
        if (operator.owner != msg.sender && msg.sender != dao) revert PermissionDenied();

        operators[_id].owner = _owner;

        emit NodeOperatorOwnerAddressSet(_id, operator.name, _owner);
    }

    /**
     * @notice set operator setting
     */
    function setOperatorSetting(
        uint256 _id,
        string calldata _name,
        address _controllerAddress,
        address[] calldata _rewardAddresses,
        uint256[] calldata _ratios
    ) public operatorExists(_id) {
        NodeOperator memory operator = operators[_id];

        if (msg.sender != operator.owner) revert PermissionDenied();

        if (bytes(_name).length != 0) {
            operators[_id].name = _name;
            emit NodeOperatorNameSet(_id, _name);
        }
        if (_controllerAddress != address(0)) {
            // The same address can only be used once
            if (usedControllerAddress[_controllerAddress]) revert ControllerAddrUsed();

            if (operator.owner != msg.sender) revert PermissionDenied();
            if (trustedControllerAddress[operator.controllerAddress] == _id) {
                trustedControllerAddress[operator.controllerAddress] = 0;
                trustedControllerAddress[_controllerAddress] = _id;
            }

            // Update the control address set to ensure that the operatorid can be obtained according to the control address
            controllerAddress[operator.controllerAddress] = 0;
            controllerAddress[_controllerAddress] = _id;
            operators[_id].controllerAddress = _controllerAddress;
            usedControllerAddress[_controllerAddress] = true;

            emit NodeOperatorControllerAddressSet(_id, operator.name, _controllerAddress);
        }
        if (_rewardAddresses.length != 0) {
            _setNodeOperatorRewardAddress(_id, _rewardAddresses, _ratios);
            emit NodeOperatorRewardAddressSet(_id, _rewardAddresses, _ratios);
        }
    }

    /**
     * @notice set contract setting
     */
    function setNodeOperatorRegistrySetting(
        address _dao,
        address _daoVaultAddress,
        address _liquidStakingContractAddress,
        address _operatorSlashContractAddress,
        address _vaultFactoryContractAddress,
        address _largeStakingContractAddress,
        uint256 _defaultOperatorCommission,
        uint256 _registrationFee,
        uint256 _permissionlessBlockNumber
    ) public onlyDao {
        if (_dao != address(0)) {
            emit DaoAddressChanged(dao, _dao);
            dao = _dao;
        }

        if (_daoVaultAddress != address(0)) {
            emit DaoVaultAddressChanged(daoVaultAddress, _daoVaultAddress);
            daoVaultAddress = _daoVaultAddress;
        }

        if (_liquidStakingContractAddress != address(0)) {
            emit LiquidStakingChanged(address(liquidStakingContract), _liquidStakingContractAddress);
            liquidStakingContract = ILiquidStaking(_liquidStakingContractAddress);
        }

        if (_operatorSlashContractAddress != address(0)) {
            emit OperatorSlashContractSet(address(operatorSlashContract), _operatorSlashContractAddress);
            operatorSlashContract = IOperatorSlash(_operatorSlashContractAddress);
        }

        if (_vaultFactoryContractAddress != address(0)) {
            emit VaultFactorContractSet(address(vaultFactoryContract), _vaultFactoryContractAddress);
            vaultFactoryContract = IELVaultFactory(_vaultFactoryContractAddress);
        }

        if (_defaultOperatorCommission != 0) {
            if (_defaultOperatorCommission >= 5000) revert InvalidCommission();
            emit DefaultOperatorCommissionRateChanged(defaultOperatorCommission, _defaultOperatorCommission);
            defaultOperatorCommission = _defaultOperatorCommission;
        }

        if (_registrationFee != 0) {
            emit RegistrationFeeChanged(registrationFee, _registrationFee);
            registrationFee = _registrationFee;
        }

        if (_permissionlessBlockNumber != 0) {
            if (permissionlessBlockNumber != 0) revert PermissionlessPhaseStart();
            if (_permissionlessBlockNumber <= block.number) revert InvalidParameter();
            permissionlessBlockNumber = _permissionlessBlockNumber;
            emit PermissionlessBlockNumberSet(_permissionlessBlockNumber);
        }

        if (_largeStakingContractAddress != address(0)) {
            emit LargeStakingChanged(address(largeStakingContract), _largeStakingContractAddress);
            largeStakingContract = ILargeStaking(_largeStakingContractAddress);
        }
    }

    /**
     * @notice transfer amount to an address
     */
    function transfer(uint256 _amount, address _to) internal {
        if (_to == address(0)) revert InvalidAddr();
        payable(_to).transfer(_amount);
        emit Transferred(_to, _amount);
    }

    /**
     * @notice Returns total number of node operators
     */
    function getNodeOperatorsCount() external view returns (uint256) {
        return totalOperators;
    }
}
