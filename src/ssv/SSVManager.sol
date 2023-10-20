// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/ssv/SSVCluster.sol";
import "src/interfaces/ISSV.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";

contract SSVManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public dao;
    address public beacon;
    address public ssvNetwork;
    address public ssvToken;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;

    // key is operatorId, value is ssvClustersProxy address
    mapping(uint256 => address) internal ssvClusters;
    mapping(uint64 => bool) public ssvOperatorWhitelist;

    address public stakingManager;
    bool public permissionless;

    event SSVClusterProxyDeployed(uint256 _nodeDaoOperatorId, address _ssvClusterProxyAddress);
    event SSVOperatorSet(uint64[] _operatorIds, bool _status);
    event DaoAddressChanged(address _oldDao, address _dao);
    event SSVValidatorRegistered(
        uint256 _nodeDaoOperatorId, bytes _publicKey, uint64[] _ssvOperatorIds, uint256 _amount
    );
    event SSVValidatorRemoved(uint256 _nodeDaoOperatorId, bytes _publicKey, uint64[] _ssvOperatorIds);
    event ClusterReactivated(uint256 _nodeDaoOperatorId, uint64[] _ssvOperatorIds, uint256 amount);
    event ClusterDeposited(uint256 _nodeDaoOperatorId, address _ssvCluster, uint64[] _ssvOperatorIds, uint256 _amount);
    event ClusterWithdrawn(uint256 _nodeDaoOperatorId, uint64[] _ssvOperatorIds, uint256 _tokenAmount);
    event FeeRecipientAddressUpdated(uint256 _nodeDaoOperatorId, address _vaultContractAddress);
    event TransferSSV(uint256 _nodeDaoOperatorId, address _to, uint256 _amount);
    event ApproveSSV(uint256 _nodeDaoOperatorId, address _ssvNetwork, uint256 _amount);
    event SSVOperatorPermissionless(uint256 _blockNumber, bool _permissionless, bool _status);

    error InvalidAddr();
    error PermissionDenied();
    error RequireOperatorTrusted();
    error RequireSSVOperatorTrusted();
    error SSVClusterNotDeployed();
    error InvalidParameter();

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    function initialize(
        address _ssvClusterImplementationAddress,
        address _dao,
        address _ssvNetwork,
        address _ssvToken,
        address _nodeOperatorRegistryContract,
        address _stakingManager
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        if (
            _ssvClusterImplementationAddress == address(0) || _dao == address(0) || _ssvNetwork == address(0)
                || _ssvToken == address(0) || _nodeOperatorRegistryContract == address(0)
        ) {
            revert InvalidAddr();
        }

        UpgradeableBeacon _beacon = new UpgradeableBeacon(
            _ssvClusterImplementationAddress
        );

        _beacon.transferOwnership(_dao);
        beacon = address(_beacon);
        dao = _dao;
        ssvNetwork = _ssvNetwork;
        ssvToken = _ssvToken;
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContract);
        stakingManager = _stakingManager;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setSSVOperator(uint64[] memory _operatorIds, bool _status) public onlyDao {
        for (uint256 i = 0; i < _operatorIds.length;) {
            ssvOperatorWhitelist[_operatorIds[i]] = _status;
            unchecked {
                ++i;
            }
        }
        emit SSVOperatorSet(_operatorIds, _status);
    }

    /// @notice Registers a new validator on the SSV Network
    function registerValidator(
        uint256 _nodeDaoOperatorId,
        bytes calldata _publicKey,
        uint64[] memory _ssvOperatorIds,
        bytes calldata _sharesData,
        uint256 _amount,
        ISSV.Cluster memory _cluster
    ) external {
        if (msg.sender != stakingManager) revert PermissionDenied();

        if (!permissionless) {
            // check ssv operators
            for (uint256 i = 0; i < _ssvOperatorIds.length;) {
                if (!ssvOperatorWhitelist[_ssvOperatorIds[i]]) {
                    revert RequireSSVOperatorTrusted();
                }
                unchecked {
                    ++i;
                }
            }
        }

        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        ISSV(ssvCluster).registerValidator(_publicKey, _ssvOperatorIds, _sharesData, _amount, _cluster);
        emit SSVValidatorRegistered(_nodeDaoOperatorId, _publicKey, _ssvOperatorIds, _amount);
    }

    /// @notice Removes an existing validator from the SSV Network
    function removeValidator(
        uint256 _nodeDaoOperatorId,
        bytes calldata _publicKey,
        uint64[] memory _ssvOperatorIds,
        ISSV.Cluster memory _cluster
    ) external {
        _checkOperatorPermissions(_nodeDaoOperatorId, false);
        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        ISSV(ssvCluster).removeValidator(_publicKey, _ssvOperatorIds, _cluster);
        emit SSVValidatorRemoved(_nodeDaoOperatorId, _publicKey, _ssvOperatorIds);
    }

    /// @notice Reactivates a cluster
    function reactivate(
        uint256 _nodeDaoOperatorId,
        uint64[] memory _ssvOperatorIds,
        uint256 _amount,
        ISSV.Cluster memory _cluster
    ) external {
        _checkOperatorPermissions(_nodeDaoOperatorId, false);
        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        ISSV(ssvCluster).reactivate(_ssvOperatorIds, _amount, _cluster);
        emit ClusterReactivated(_nodeDaoOperatorId, _ssvOperatorIds, _amount);
    }

    /// @notice Deposits tokens into a cluster
    function deposit(
        uint256 _nodeDaoOperatorId,
        uint64[] memory _ssvOperatorIds,
        uint256 _amount,
        ISSV.Cluster memory _cluster
    ) external {
        _checkOperatorPermissions(_nodeDaoOperatorId, false);
        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        ISSV(ssvCluster).deposit(ssvCluster, _ssvOperatorIds, _amount, _cluster);
        emit ClusterDeposited(_nodeDaoOperatorId, ssvCluster, _ssvOperatorIds, _amount);
    }

    /// @notice Withdraws tokens from a cluster
    function withdraw(
        uint256 _nodeDaoOperatorId,
        uint64[] memory _ssvOperatorIds,
        uint256 _tokenAmount,
        ISSV.Cluster memory _cluster
    ) external {
        _checkOperatorPermissions(_nodeDaoOperatorId, false);
        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        ISSV(ssvCluster).withdraw(_ssvOperatorIds, _tokenAmount, _cluster);
        emit ClusterWithdrawn(_nodeDaoOperatorId, _ssvOperatorIds, _tokenAmount);
    }

    /// @notice set ssv validator fee recipient address
    function setFeeRecipientAddress(uint256 _nodeDaoOperatorId) external {
        _checkOperatorPermissions(_nodeDaoOperatorId, false);
        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_nodeDaoOperatorId);
        ISSV(ssvCluster).setFeeRecipientAddress(vaultContractAddress);
        emit FeeRecipientAddressUpdated(_nodeDaoOperatorId, vaultContractAddress);
    }

    /// @notice transfer ssv token
    function transfer(uint256 _nodeDaoOperatorId, address _to, uint256 _amount) external returns (bool) {
        _checkOperatorPermissions(_nodeDaoOperatorId, true);
        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        emit TransferSSV(_nodeDaoOperatorId, _to, _amount);
        return ISSV(ssvCluster).transfer(_to, _amount);
    }

    /// @notice approve ssv token
    function approve(uint256 _nodeDaoOperatorId, uint256 _amount) external returns (bool) {
        _checkOperatorPermissions(_nodeDaoOperatorId, false);
        address ssvCluster = getSSVCluster(_nodeDaoOperatorId);
        address _ssvNetwork = ssvNetwork;
        emit ApproveSSV(_nodeDaoOperatorId, _ssvNetwork, _amount);
        return ISSV(ssvCluster).approve(_ssvNetwork, _amount);
    }

    function getSSVCluster(uint256 _operatorId) public view returns (address) {
        address ssvClusterProxy;
        ssvClusterProxy = ssvClusters[_operatorId];
        if (ssvClusterProxy == address(0)) {
            revert SSVClusterNotDeployed();
        }

        return ssvClusterProxy;
    }

    function startupSSV(uint256 _operatorId) public {
        _checkOperatorPermissions(_operatorId, true);
        address ssvClusterProxy;
        ssvClusterProxy = ssvClusters[_operatorId];
        if (ssvClusterProxy == address(0)) {
            ssvClusterProxy = address(
                new BeaconProxy(beacon, abi.encodeWithSelector(SSVCluster.initialize.selector, address(this), ssvNetwork, ssvToken))
            );

            emit SSVClusterProxyDeployed(_operatorId, ssvClusterProxy);
            ssvClusters[_operatorId] = ssvClusterProxy;

            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
            ISSV(ssvClusterProxy).setFeeRecipientAddress(vaultContractAddress);
        }
    }

    function _checkOperatorPermissions(uint256 _operatorId, bool _mustOperatorOwner) internal view {
        (,, address owner, address controllerAddress,) =
            nodeOperatorRegistryContract.getNodeOperator(_operatorId, false);
        if (_mustOperatorOwner && owner != msg.sender) {
            revert PermissionDenied();
        }

        if (msg.sender != owner && msg.sender != controllerAddress) {
            revert PermissionDenied();
        }
    }

    function setDaoAddress(address _dao) external onlyOwner {
        if (_dao == address(0)) revert InvalidParameter();
        emit DaoAddressChanged(dao, _dao);
        dao = _dao;
    }

    function setSSVOperatorPermissionless(bool _status) external onlyDao {
        emit SSVOperatorPermissionless(block.number, permissionless, _status);
        permissionless = _status;
    }
}
