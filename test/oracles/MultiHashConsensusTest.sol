// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "src/utils/Array.sol";

// forge test --match-path  test/oracles/MultiHashConsensusTest.sol
contract MultiHashConsensusTest is Test {
    function setUp() public {}

    // forge test -vvvv --match-test testCompareBytes32Arrays
    function testCompareBytes32Arrays() public {
        bytes32[] memory arr1 = new bytes32[](2);
        arr1[0] = bytes32(uint256(1));
        arr1[1] = bytes32(uint256(2));

        bytes32[] memory arr2 = new bytes32[](2);
        arr2[0] = bytes32(uint256(1));
        arr2[1] = bytes32(uint256(2));

        assertTrue(Array.compareBytes32Arrays(arr1, arr2));

        arr2[0] = bytes32(uint256(2));
        arr2[1] = bytes32(uint256(1));

        assertFalse(Array.compareBytes32Arrays(arr1, arr2));
    }
}
