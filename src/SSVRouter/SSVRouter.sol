// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/SSVRouter/SSVManager.sol";
import "src/interfaces/ISSVNetwork.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";

contract SSVRoutter is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public dao;
    address public beacon;
    address public ssvNetwork;
    address public ssvToken;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;

    // key is operatorId, value is ssvManagerProxy address
    mapping(uint256 => address) public ssvManagers;
    mapping(uint256 => bool) public ssvOperatorWhitelist;

    event SSVManagerProxyDeployed(address _proxyAddress);
    event SSVOperatorSet(uint256[] _operatorIds, bool _status);

    error InvalidAddr();
    error PermissionDenied();
    error RequireOperatorTrusted();
    error RequireSSVOperatorTrusted();

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    function setSSVOperator(uint256[] memory _operatorIds, bool _status) public onlyDao {
        for (uint256 i = 0; i < _operatorIds.length;) {
            ssvOperatorWhitelist[_operatorIds[i]] = _status;
            unchecked {
                ++i;
            }
        }
        emit SSVOperatorSet(_operatorIds, _status);
    }

    function initialize(
        address _ssvManagerImplementationAddress,
        address _dao,
        address _ssvNetwork,
        address _ssvToken,
        address _nodeOperatorRegistryContract
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        if (
            _ssvManagerImplementationAddress == address(0) || _dao == address(0) || _ssvNetwork == address(0)
                || _ssvToken == address(0) || _nodeOperatorRegistryContract == address(0)
        ) {
            revert InvalidAddr();
        }

        UpgradeableBeacon _beacon = new UpgradeableBeacon(
            _ssvManagerImplementationAddress
        );

        _beacon.transferOwnership(_dao);
        beacon = address(_beacon);
        dao = _dao;
        ssvNetwork = _ssvNetwork;
        ssvToken = _ssvToken;
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContract);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Registers a new validator on the SSV Network
    function registerValidator(
        bytes calldata publicKey,
        uint64[] memory operatorIds,
        bytes calldata sharesData,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    ) external {
        uint256 _operatorId = getOperatorId();

        // check ssv operators
        for (uint256 i = 0; i < operatorIds.length;) {
            if (!ssvOperatorWhitelist[operatorIds[i]]) {
                revert RequireSSVOperatorTrusted();
            }
            unchecked {
                ++i;
            }
        }

        address ssvManager = getSSVManager(_operatorId);
        ISSVNetwork(ssvManager).registerValidator(publicKey, operatorIds, sharesData, amount, cluster);
    }

    /// @notice Removes an existing validator from the SSV Network
    function removeValidator(
        bytes calldata publicKey,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external {
        uint256 _operatorId = getOperatorId();
        address ssvManager = getSSVManager(_operatorId);
        ISSVNetwork(ssvManager).removeValidator(publicKey, operatorIds, cluster);
    }

    /// @notice Reactivates a cluster
    function reactivate(uint64[] memory operatorIds, uint256 amount, ISSVNetworkCore.Cluster memory cluster) external {
        uint256 _operatorId = getOperatorId();
        address ssvManager = getSSVManager(_operatorId);
        ISSVNetwork(ssvManager).reactivate(operatorIds, amount, cluster);
    }

    /// @notice Deposits tokens into a cluster
    function deposit(address owner, uint64[] memory operatorIds, uint256 amount, ISSVNetworkCore.Cluster memory cluster)
        external
    {
        uint256 _operatorId = getOperatorId();
        address ssvManager = getSSVManager(_operatorId);
        ISSVNetwork(ssvManager).deposit(owner, operatorIds, amount, cluster);
    }

    /// @notice Withdraws tokens from a cluster
    function withdraw(uint64[] memory operatorIds, uint256 tokenAmount, ISSVNetworkCore.Cluster memory cluster)
        external
    {
        uint256 _operatorId = getOperatorId();
        address ssvManager = getSSVManager(_operatorId);
        ISSVNetwork(ssvManager).withdraw(operatorIds, tokenAmount, cluster);
    }

    /// @notice set ssv validator fee recipient address
    function setFeeRecipientAddress() external {
        uint256 _operatorId = getOperatorId();
        address ssvManager = getSSVManager(_operatorId);
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
        ISSVNetwork(ssvManager).setFeeRecipientAddress(vaultContractAddress);
    }

    /// @notice transfer ssv token
    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 _operatorId = getOperatorId();
        address ssvManager = getSSVManager(_operatorId);
        ISSVNetwork(ssvManager).transfer(to, amount);
    }

    /// @notice approve ssv token
    function approve(address spender, uint256 amount) external returns (bool) {
        uint256 _operatorId = getOperatorId();
        address ssvManager = getSSVManager(_operatorId);
        ISSVNetwork(ssvManager).approve(spender, amount);
    }

    function getSSVManager(uint256 _operatorId) internal returns (address) {
        address ssvManagerProxy;
        ssvManagerProxy = ssvManagers[_operatorId];
        if (ssvManagerProxy == address(0)) {
            ssvManagerProxy = address(
                new BeaconProxy(beacon, abi.encodeWithSelector(SSVManager.initialize.selector, address(this), ssvNetwork, ssvToken))
            );

            emit SSVManagerProxyDeployed(ssvManagerProxy);
            ssvManagers[_operatorId] = ssvManagerProxy;
        }

        return ssvManagerProxy;
    }

    function getOperatorId() internal returns (uint256) {
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        if (operatorId == 0) revert RequireOperatorTrusted();
        return operatorId;
    }
}
