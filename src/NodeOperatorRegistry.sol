// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract NodeOperatorRegistry {
    uint256 public totalOperators;

    function registerValidator(
        bytes memory pubkey,
        bytes memory signature,
        bytes32 depositDataRoot
    ) external nonReentrant {
        
    }
}
