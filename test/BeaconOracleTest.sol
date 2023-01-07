// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/oracles/BeaconOracle.sol";
import "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";

contract BeaconOracleTest is Test {
    //    event AddOracleMember(address oracleMember);
    //    event RemoveOracleMember(address oracleMember);
    //    event ResetExpectedEpochId(uint256 expectedEpochId);
    //    event ResetEpochsPerFrame(uint256 epochsPerFrame);
    //    event ReportBeacon(uint256 epochId, address oracleMember, uint256 sameReportCount);
    //    event ReportSuccess(uint256 epochId, uint32 sameReportCount, uint32 quorum);

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

    //    function setUp() public {
    //        beaconOracle = new BeaconOracle();
    //        initializer();
    //    }

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

    function testGetConfig() public {
        //        print(beaconOracle.expectedEpochId());
        assertEq(beaconOracle.epochsPerFrame(), 225);
        assertEq(beaconOracle.isQuorum(), false);
    }

    function testResetEpochsPerFrame() public {
        //        vm.expectEmit(450);
        beaconOracle.resetEpochsPerFrame(450);
    }

    function testIsReportBeacon() public {
        assertEq(beaconOracle.isReportBeacon(172531), false);
    }

    function testReportBeacon() public {
        //        vm.expectEmit(172531, 1, 1);
        //        beaconOracle.reportBeacon(172531, 123456789, 12345, "0xc0bbb890aaa33eb4af83ab649b89d8a3c1ba3f3b2814da0b676b66171274ddc3");
    }

    function convertHexStringToBytes32Array(string memory _hexString) public pure returns (bytes32[] memory) {
        bytes memory hexString = abi.encodePacked(_hexString);
        return abi.decode(hexString, (bytes32[]));
    }

    function testMerkle() public {
        bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;
        bytes32 leaf = 0x10e799df87265a6e1c8b5d60ce37fbca4a02c93b5a6a9f5895eeb41a209620f6;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0x877794ba7ca53549ef847bec0cf7a76f50f7f2c3a192f8daf952583741b8580e;
        proof[1] = 0xab2e0accab37b2e656021ad27eb3c7b975672f09b9c5e94ec87e50acad3373ec;

        bool isVerify = MerkleProof.verify(proof, root, leaf);
        assertEq(isVerify, true);
    }

    function testVerifyNftValue() public {
        bytes32 leaf = 0x2be8989c2d18158d2de1becacd0c9088ebe623f7b82d22adfc88a5d8ce455656;
        //        bytes32[] memory proof = ;
        //        assertEq(beaconOracle.verifyNftValue(172531), false);
    }

}
