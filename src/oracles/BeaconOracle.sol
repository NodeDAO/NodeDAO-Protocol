// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract BeaconOracle is ReentrancyGuardUpgradeable {
    uint128 internal constant DENOMINATION_OFFSET = 1e9;
    uint64 internal constant EPOCHS_PER_FRAME = 225;
    uint64 internal constant SLOTS_PER_EPOCH = 32;
    uint64 internal constant GENESIS_TIME = 1606824023;
    uint64 internal constant SECONDS_PER_SLOT = 12;

}
