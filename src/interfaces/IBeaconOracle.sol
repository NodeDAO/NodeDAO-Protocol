// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

/**
  * @title Beacon Oracle and Dao
  *
  * BeaconOracle data acquisition and verification
  * Dao management
  */
interface IBeaconOracle {

    // verifyNftValue
    function verifyNftValue(bytes32[] memory proof, bytes32 leaf) external view returns (bool);

    // Is a reporter
    function isReporter(address _daoMember) external view returns (bool);

}
