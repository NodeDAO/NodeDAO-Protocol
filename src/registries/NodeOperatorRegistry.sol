// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract NodeOperatorRegistry is ReentrancyGuardUpgradeable {
    uint256 public totalOperators;

    function registerValidator(
        bytes memory pubkey,
        bytes memory signature,
        bytes32 depositDataRoot
    ) external nonReentrant {
        
    }
}
