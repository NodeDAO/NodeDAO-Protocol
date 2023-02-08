// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/vault/ELVault.sol";

/**
 * @title ELVaultFactory Contract
 *
 * Vault's factory contract, which automatically creates its own vault contract for each operator
 */
contract ELVaultFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public dao;
    address public vNFTContract;
    address public liquidStakingAddress;
    address public beacon;
    address public nodeOperatorRegistryAddress;

    modifier onlyNodeOperatorRegistry() {
        require(nodeOperatorRegistryAddress == msg.sender, "Not allowed to create vault");
        _;
    }

    event ELVaultProxyDeployed(address proxyAddress);
    event NodeOperatorRegistrySet(address oldNodeOperatorRegistryAddress, address _nodeOperatorRegistryAddress);

    /**
     * @notice initialize ELVaultFactory Contract
     * @param _ELVaultImplementationAddress vault contract implementation address
     * @param _nVNFTContractAddress vNFT contract address
     * @param _liquidStakingAddress liquidStaking contract address
     * @param _dao Dao Address
     */
    function initialize(
        address _ELVaultImplementationAddress,
        address _nVNFTContractAddress,
        address _liquidStakingAddress,
        address _dao
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        UpgradeableBeacon _beacon = new UpgradeableBeacon(
            _ELVaultImplementationAddress
        );

        _beacon.transferOwnership(_dao);
        beacon = address(_beacon);
        vNFTContract = _nVNFTContractAddress;
        dao = _dao;
        liquidStakingAddress = _liquidStakingAddress;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice create vault contract
     * @param operatorId operator id
     */
    function create(uint256 operatorId) external onlyNodeOperatorRegistry returns (address) {
        address proxyAddress = address(
            new BeaconProxy(beacon, abi.encodeWithSelector(ELVault.initialize.selector, vNFTContract, dao, operatorId, liquidStakingAddress, nodeOperatorRegistryAddress))
        );
        emit ELVaultProxyDeployed(proxyAddress);
        return proxyAddress;
    }

    /**
     * @notice set NodeOperatorRegistry contract address
     * @param _nodeOperatorRegistryAddress nodeOperatorRegistry contract Address
     */
    function setNodeOperatorRegistry(address _nodeOperatorRegistryAddress) public onlyOwner {
        address oldNodeOperatorRegistryAddress = nodeOperatorRegistryAddress;
        nodeOperatorRegistryAddress = _nodeOperatorRegistryAddress;
        emit NodeOperatorRegistrySet(oldNodeOperatorRegistryAddress, _nodeOperatorRegistryAddress);
    }
}
