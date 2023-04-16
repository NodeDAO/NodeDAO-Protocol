// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title Treasury
 */
contract Treasury is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public dao;

    event DaoAddressChanged(address _oldDao, address _dao);
    event Transferred(address _to, uint256 _amount);

    error PermissionDenied();
    error InvalidAddr();

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    /**
     * @notice Initializes the DaoVault
     * @dev initializer - A modifier that defines a protected initializer function that can be invoked at most once
     * @param _dao dao address
     */
    function initialize(address _dao) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        dao = _dao;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice transfer ETH
     * @param _amount transfer amount
     * @param _to transfer to address
     */
    function transfer(uint256 _amount, address _to) external nonReentrant onlyDao {
        if (_to == address(0)) revert InvalidAddr();
        payable(_to).transfer(_amount);
        emit Transferred(_to, _amount);
    }

    /**
     * @notice set dao address
     * @param _dao new dao address
     */
    function setDaoAddress(address _dao) external onlyOwner {
        if (_dao == address(0)) revert InvalidAddr();
        emit DaoAddressChanged(dao, _dao);
        dao = _dao;
    }

    receive() external payable {}
}
