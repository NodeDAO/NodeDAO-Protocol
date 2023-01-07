// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/oracles/BeaconOracle.sol";

contract BeaconOracleTest is Test {

    BeaconOracle beaconOracle;
    address _dao = address(1);
    address _liquidStakingContract = address(2);
    address _nodeOperatorsContract = address(3);

    function initializer() private {
        address[] memory _oracleMembers = new address[](3);
        _oracleMembers[0] = address(0x1234567812345678123456781234567812345678);
        _oracleMembers[1] = address(0x2345678923456789234567892345678923456789);
        _oracleMembers[2] = address(0x3456789034567890345678903456789034567890);

        beaconOracle.initialize(_dao, _liquidStakingContract, _nodeOperatorsContract);
    }

    function setUp() public {
        beaconOracle = new BeaconOracle();
        initializer();
    }

    function testDao() public {
        assertEq(beaconOracle.dao(), _dao);
    }

    function testAddOracleMember() public {
        beaconOracle.addOracleMember(address(0x1234567812345678123456781234567812345678));
    }

    function testGetOracleMemberCount() public {
        assertEq(beaconOracle.oracleMemberCount(), 1);
    }

    function testIsOracleMember() public {
        bool isOracleMember = beaconOracle.isOracleMember(address(0x1234567812345678123456781234567812345678));
        assertEq(isOracleMember, true);
    }

    function testRemoveOracleMember() public {
        beaconOracle.removeOracleMember(address(0x1234567812345678123456781234567812345678));
    }


    function testGetQuorum() public {
        uint32 quorum = beaconOracle.getQuorum();
        assertEq(quorum, 0);
    }

}
