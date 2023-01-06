// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

/**
  * @title Beacon Oracle and Dao
  *
  * BeaconOracle data acquisition and verification
  * Dao management
  */
interface IBeaconOracle {
    // TODO:@renshiwei 2023/1/5 description: verifyNftValue function
    function verifyNftValue(bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID) external view returns (bool);

    // Is a member of the dao
    function isDaoMember(address _daoMember) external view returns (bool);

}
