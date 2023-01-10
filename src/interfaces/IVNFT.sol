// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

interface IVNFT {
    function activeValidators() external view returns (bytes[] memory);
}
