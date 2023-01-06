// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

interface ILiquidStaking {

    function handleOracleReport(uint256  _data, bytes32 nodeRankingCommitment) external;

    function getTotalPooledEther() external returns(uint256);


}