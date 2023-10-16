// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/ISSVManager.sol";

contract StakingManager is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint256 internal constant DEPOSIT_SIZE = 32 ether;

    address public dao;

    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    ILiquidStaking public liquidStakingContract;
    ISSVManager public ssvManagerContract;

    // key is operatorId, value is the remaining staking amount
    mapping(uint256 => uint256) public ssvStakingQuota;

    error PermissionDenied();
    error InvalidParameter();
    error RequireOperatorTrusted();
    error InvalidAmount();
    error InsufficientQuota();
    error NftValidatorRequireRegistration();
    error SSVValidatorRequireRegistration();

    event SSVStakingQuotaSet(uint256 _oldQuota, uint256 _newQuota);
    event ValidatorRegistered(uint256 operatorId, bytes[] _pubkeys);
    event SSVValidatorRegistered(uint256 operatorId, bytes _pubkey);

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    function initialize(
        address _dao,
        address _nodeOperatorRegistryContractAddress,
        address _liquidStakingContractAddress,
        address _ssvManagerContractAddress
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContractAddress);
        liquidStakingContract = ILiquidStaking(_liquidStakingContractAddress);
        ssvManagerContract = ISSVManager(_ssvManagerContractAddress);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setSSVStakingQuota(uint256 _operatorId, uint256 _quota) public onlyDao {
        emit SSVStakingQuotaSet(ssvStakingQuota[_operatorId], _quota);
        ssvStakingQuota[_operatorId] = _quota;
    }

    function registerValidator(
        bytes[] calldata _pubkeys,
        bytes[] calldata _signatures,
        bytes32[] calldata _depositDataRoots
    ) external {
        if (_pubkeys.length != _signatures.length || _pubkeys.length != _depositDataRoots.length) {
            revert InvalidParameter();
        }

        // must be a trusted operator
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        if (operatorId == 0) revert RequireOperatorTrusted();

        uint256 quota = ssvStakingQuota[operatorId];
        if (quota >= DEPOSIT_SIZE) {
            uint256 nftPoolBalance = liquidStakingContract.operatorNftPoolBalances(operatorId);
            uint256 nftValidatorCounts = nftPoolBalance / DEPOSIT_SIZE;
            if (_pubkeys.length > nftValidatorCounts) revert SSVValidatorRequireRegistration();
        }

        liquidStakingContract.registerValidator(operatorId, _pubkeys, _signatures, _depositDataRoots);
        emit ValidatorRegistered(operatorId, _pubkeys);
    }

    function registerSSVValidator(
        bytes calldata _pubkey,
        bytes calldata _signature,
        bytes32 _depositDataRoot,
        uint64[] memory operatorIds,
        bytes calldata sharesData,
        uint256 amount,
        ISSV.Cluster memory cluster
    ) external {
        // must be a trusted operator
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        if (operatorId == 0) revert RequireOperatorTrusted();

        uint256 quota = ssvStakingQuota[operatorId];
        if (quota < DEPOSIT_SIZE) revert InsufficientQuota();

        uint256 nftPoolBalance = liquidStakingContract.operatorNftPoolBalances(operatorId);
        if (nftPoolBalance != 0) revert NftValidatorRequireRegistration();

        bytes[] memory _pubkeys = new bytes[](1);
        bytes[] memory _signatures = new bytes[](1);
        bytes32[] memory _depositDataRoots = new bytes32[](1);
        _pubkeys[0] = _pubkey;
        _signatures[0] = _signature;
        _depositDataRoots[0] = _depositDataRoot;
        liquidStakingContract.registerValidator(operatorId, _pubkeys, _signatures, _depositDataRoots);

        ssvManagerContract.registerValidator(operatorId, _pubkeys[0], operatorIds, sharesData, amount, cluster);
        ssvStakingQuota[operatorId] -= DEPOSIT_SIZE;

        emit SSVValidatorRegistered(operatorId, _pubkeys[0]);
    }
}
