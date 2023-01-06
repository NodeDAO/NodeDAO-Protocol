// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

interface ILiquidStaking {

    function handleOracleReport(uint64 _beaconBalance, uint32 _beaconValidators, bytes32 nodeRankingCommitment) external;

    function getTotalPooledEther() external returns (uint256);


}
