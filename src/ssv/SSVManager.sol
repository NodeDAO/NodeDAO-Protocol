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

    event SSVClusterProxyDeployed(address _proxyAddress);
    event SSVOperatorSet(uint64[] _operatorIds, bool _status);

    error InvalidAddr();
    error PermissionDenied();
    error RequireOperatorTrusted();
    error RequireSSVOperatorTrusted();
    error SSVClusterNotDeployed();

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
        uint256 _operatorId,
        bytes calldata publicKey,
        uint64[] memory operatorIds,
        bytes calldata sharesData,
        uint256 amount,
        ISSV.Cluster memory cluster
    ) external {
        if (msg.sender != stakingManager) revert PermissionDenied();

        // check ssv operators
        for (uint256 i = 0; i < operatorIds.length;) {
            if (!ssvOperatorWhitelist[operatorIds[i]]) {
                revert RequireSSVOperatorTrusted();
            }
            unchecked {
                ++i;
            }
        }

        address ssvCluster = getSSVCluster(_operatorId);
        ISSV(ssvCluster).registerValidator(publicKey, operatorIds, sharesData, amount, cluster);
    }

    /// @notice Removes an existing validator from the SSV Network
    function removeValidator(bytes calldata publicKey, uint64[] memory operatorIds, ISSV.Cluster memory cluster)
        external
    {
        uint256 _operatorId = getOperatorId();
        address ssvCluster = getSSVCluster(_operatorId);
        ISSV(ssvCluster).removeValidator(publicKey, operatorIds, cluster);
    }

    /// @notice Reactivates a cluster
    function reactivate(uint64[] memory operatorIds, uint256 amount, ISSV.Cluster memory cluster) external {
        uint256 _operatorId = getOperatorId();
        address ssvCluster = getSSVCluster(_operatorId);
        ISSV(ssvCluster).reactivate(operatorIds, amount, cluster);
    }

    /// @notice Deposits tokens into a cluster
    function deposit(address owner, uint64[] memory operatorIds, uint256 amount, ISSV.Cluster memory cluster)
        external
    {
        uint256 _operatorId = getOperatorId();
        address ssvCluster = getSSVCluster(_operatorId);
        ISSV(ssvCluster).deposit(owner, operatorIds, amount, cluster);
    }

    /// @notice Withdraws tokens from a cluster
    function withdraw(uint64[] memory operatorIds, uint256 tokenAmount, ISSV.Cluster memory cluster) external {
        uint256 _operatorId = getOperatorId();
        address ssvCluster = getSSVCluster(_operatorId);
        ISSV(ssvCluster).withdraw(operatorIds, tokenAmount, cluster);
    }

    /// @notice set ssv validator fee recipient address
    function setFeeRecipientAddress() external {
        uint256 _operatorId = getOperatorId();
        address ssvCluster = getSSVCluster(_operatorId);
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
        ISSV(ssvCluster).setFeeRecipientAddress(vaultContractAddress);
    }

    /// @notice transfer ssv token
    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 _operatorId = getOperatorId();
        address ssvCluster = getSSVCluster(_operatorId);
        return ISSV(ssvCluster).transfer(to, amount);
    }

    /// @notice approve ssv token
    function approve(address spender, uint256 amount) external returns (bool) {
        uint256 _operatorId = getOperatorId();
        address ssvCluster = getSSVCluster(_operatorId);
        return ISSV(ssvCluster).approve(spender, amount);
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
        address ssvClusterProxy;
        ssvClusterProxy = ssvClusters[_operatorId];
        if (ssvClusterProxy == address(0)) {
            ssvClusterProxy = address(
                new BeaconProxy(beacon, abi.encodeWithSelector(SSVCluster.initialize.selector, address(this), ssvNetwork, ssvToken))
            );

            emit SSVClusterProxyDeployed(ssvClusterProxy);
            ssvClusters[_operatorId] = ssvClusterProxy;

            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
            ISSV(ssvClusterProxy).setFeeRecipientAddress(vaultContractAddress);
        }
    }

    function getOperatorId() internal view returns (uint256) {
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        if (operatorId == 0) revert RequireOperatorTrusted();
        return operatorId;
    }
}
