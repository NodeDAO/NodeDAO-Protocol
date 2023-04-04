// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;
import {WithdrawInfo, ExitValidatorInfo} from "src/library/ConsensusStruct.sol";
/**
 * @title Interface for IVaultManager
 * @notice Vault will manage methods for rewards, commissions, tax
 */
interface IVaultManager {
    function settleAndReinvestElReward(uint256[] memory _operatorIds) external;
    function reportConsensusData(
        WithdrawInfo[] memory _withdrawInfo,
        ExitValidatorInfo[] memory _exitValidatorInfo,
        uint256[] memory _delayedExitTokenIds,
        uint256 _thisTotalWithdrawAmount
    ) external;
}
