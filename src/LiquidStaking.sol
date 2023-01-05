// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LiquidStaking is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function stake(address referral, address node_operator) external payable nonReentrant {

    }
}
