// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "./ISSV.sol";

interface ISSVManager {
    /// @notice Registers a new validator on the SSV Network
    function registerValidator(
        uint256 _operatorId,
        bytes calldata publicKey,
        uint64[] memory operatorIds,
        bytes calldata sharesData,
        uint256 amount,
        ISSV.Cluster memory cluster
    ) external;
}
