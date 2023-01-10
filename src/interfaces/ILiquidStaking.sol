// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

interface ILiquidStaking {

    function getTotalPooledEther() external returns (uint256);

    function computeWithdrawableEther() external view returns (uint256);
}
