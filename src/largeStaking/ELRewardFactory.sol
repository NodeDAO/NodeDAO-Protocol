// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/largeStaking/ELReward.sol";
import "src/interfaces/IELRewardFactory.sol";

/**
 * @title ELRewardFactory Contract
 *
 * Vault's factory contract, which automatically creates its own vault contract for each operator
 */
contract ELRewardFactory is IELRewardFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public dao;
    address public beacon;

    error InvalidAddr();

    /**
     * @notice initialize ELRewardFactory Contract
     * @param _ELRewardImplementationAddress vault contract implementation address
     * @param _dao Dao Address
     */
    function initialize(address _ELRewardImplementationAddress, address _dao) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        if (_ELRewardImplementationAddress == address(0) || _dao == address(0)) {
            revert InvalidAddr();
        }

        UpgradeableBeacon _beacon = new UpgradeableBeacon(
            _ELRewardImplementationAddress
        );

        _beacon.transferOwnership(_dao);
        beacon = address(_beacon);
        dao = _dao;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice create vault contract
     * @param _operatorId operator id
     */
    function create(uint256 _operatorId, address _manager) external returns (address) {
        address proxyAddress = address(
            new BeaconProxy(beacon, abi.encodeWithSelector(ELReward.initialize.selector, dao, _manager, _operatorId))
        );
        emit ELRewardProxyDeployed(proxyAddress);
        return proxyAddress;
    }
}
