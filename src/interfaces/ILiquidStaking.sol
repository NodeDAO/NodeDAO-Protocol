// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

interface ILiquidStaking {

    function handleOracleReport(uint64 _beaconBalance, uint32 _beaconValidators) external;

    function getTotalPooledEther() external returns (uint256);

    function computeWithdrawableEther() external view returns (uint256);

    function check32ETHOperatorBalance(uint256 operator) external view returns(uint256);

}
