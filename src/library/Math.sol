// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

library MathUtil {
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Tests if x ∈ [a, b) (mod n)
    ///
    function pointInHalfOpenIntervalModN(uint256 x, uint256 a, uint256 b, uint256 n) internal pure returns (bool) {
        return (x + n - a) % n < (b - a) % n;
    }

    /// @notice Tests if x ∈ [a, b] (mod n)
    ///
    function pointInClosedIntervalModN(uint256 x, uint256 a, uint256 b, uint256 n) internal pure returns (bool) {
        return (x + n - a) % n <= (b - a) % n;
    }
}
