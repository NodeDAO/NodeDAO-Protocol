// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LiquidStaking is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    
    bytes private withdrawalCredentials;

    function initialize( bytes memory withdrawalCreds, address _validatorNft  ) external initializer {
        __ReentrancyGuard_init();
        withdrawalCredentials = withdrawalCreds;
 
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function stake(address referral, address node_operator) external payable nonReentrant {
        require(msg.value != 0, "Stake amount must not be Zero");
        require(msg.value >= 100 wei, "Stake amount must be minimum  100 wei");
        require(referral != address(0x0), "Referral address must be provided");
    }
}
