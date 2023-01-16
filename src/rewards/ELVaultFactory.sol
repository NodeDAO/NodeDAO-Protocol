// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "./ELVault.sol";

contract ELVaultFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public dao;
    address public vNFTContract;
    address public beacon;
    address[] public ELVaults;
    mapping(uint256 => address) operatorVaults;

    event ELVaultProxyDeployed(address proxyAddress);

    function initialize(address _ELVaultImplementationAddress, address _nVNFTContractAddress, address _dao)
        external
        initializer
    {
        __Ownable_init();
        __UUPSUpgradeable_init();

        UpgradeableBeacon _beacon = new UpgradeableBeacon(
            _ELVaultImplementationAddress
        );
        _beacon.transferOwnership(msg.sender);
        beacon = address(_beacon);
        vNFTContract = _nVNFTContractAddress;
        dao = _dao;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function create(uint256 operatorId) external onlyOwner returns (address) {
        // require operator exists

        address proxyAddress = address(
            new BeaconProxy(beacon, abi.encodeWithSelector(ELVault.initialize.selector, vNFTContract, dao, operatorId))
        );
        ELVaults.push(proxyAddress);
        emit ELVaultProxyDeployed(proxyAddress);
        operatorVaults[operatorId] = proxyAddress;
        return proxyAddress;
    }

    /**
     * @notice Get information about an operator vault contract address
     * @param _id operator id
     */
    function getNodeOperatorVaultContract(uint256 _id) external view returns (address vaultContractAddress) {
        return operatorVaults[_id];
    }
}
