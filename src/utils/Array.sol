// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

library Array {
    function compareBytes32Arrays(bytes32[] memory arr1, bytes32[] memory arr2) public pure returns (bool) {
        if (arr1.length != arr2.length) {
            return false;
        }

        bytes32 hash1 = keccak256(abi.encodePacked(arr1));
        bytes32 hash2 = keccak256(abi.encodePacked(arr2));

        return hash1 == hash2;
    }
}
