// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

import "src/oracles/WithdrawOracle.sol";
import "src/library/UnstructuredStorage.sol";

interface ITimeProvider {
    function getTime() external view returns (uint256);
}

contract WithdrawOracleWithTimer is WithdrawOracle {
    using UnstructuredStorage for bytes32;

    function getTime() external view returns (uint256) {
        return _getTime();
    }

    function _getTime() internal view override returns (uint256) {
        address consensus = CONSENSUS_CONTRACT_POSITION.getStorageAddress();
        return ITimeProvider(consensus).getTime();
    }

    function getDataProcessingState() external view returns (DataProcessingState memory) {
        return _storageDataProcessingState().value;
    }
}
