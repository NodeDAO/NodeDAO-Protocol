// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";

/**
 * @title Treasury
 */
contract NodeDaoTreasury is Ownable, ReentrancyGuard {
    address public dao;

    event DaoAddressChanged(address _oldDao, address _dao);
    event Transferred(address _to, uint256 _amount);

    error PermissionDenied();
    error InvalidAddr();

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    constructor(address _dao) {
        dao = _dao;
    }

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
