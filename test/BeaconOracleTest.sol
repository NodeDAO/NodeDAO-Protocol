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
        beaconOracle.initialize(_dao, _liquidStakingContract, _nodeOperatorsContract);
    }

    function setUp() public {
        vm.warp(1606824300);
        //        vm.warp(beaconOracle.GENESIS_TIME);
        beaconOracle = new BeaconOracle();
        initializer();
    }

    function testDao() public {
        assertEq(beaconOracle.dao(), _dao);
    }

    function testAddOracleMember() public {
        vm.prank(address(1));
        beaconOracle.addOracleMember(address(0x1234567812345678123456781234567812345678));
    }

    function testFailAuthOracleMember() public {
        beaconOracle.addOracleMember(address(0x1234567812345678123456781234567812345678));
        vm.expectRevert("AUTH_FAILED");
    }

    function testGetOracleMemberCount() public {
        testAddOracleMember();
        assertEq(beaconOracle.oracleMemberCount(), 1);
    }

    function testIsOracleMember() public {
        testAddOracleMember();
        bool isOracleMember = beaconOracle.isOracleMember(address(0x1234567812345678123456781234567812345678));
        assertEq(isOracleMember, true);
    }

    function testRemoveOracleMember() public {
        vm.prank(address(1));
        beaconOracle.addOracleMember(address(0x1234567812345678123456781234567812345678));
        assertEq(beaconOracle.oracleMemberCount(), 1);
        vm.prank(address(1));
        beaconOracle.removeOracleMember(address(0x1234567812345678123456781234567812345678));
        assertEq(beaconOracle.oracleMemberCount(), 0);
    }

    function testGetQuorum() public {
        uint32 quorum = beaconOracle.getQuorum();
        assertEq(quorum, 0);
    }


    function testGetConfig() public {
        console.log(beaconOracle.expectedEpochId());
        assertEq(beaconOracle.epochsPerFrame(), 225);
        assertFalse(beaconOracle.isQuorum());
    }

    function testResetEpochsPerFrame() public {
        vm.prank(address(1));
        beaconOracle.resetEpochsPerFrame(450);
        assertEq(beaconOracle.epochsPerFrame(), 450);
    }

    function testIsReportBeacon() public {
        assertFalse(beaconOracle.isReportBeacon(172531));
    }

    function testReportBeacon() public {
        //        vm.expectEmit(172531, 1, 1);
        //        beaconOracle.reportBeacon(172531, 123456789, 12345, "0xc0bbb890aaa33eb4af83ab649b89d8a3c1ba3f3b2814da0b676b66171274ddc3");
    }

    //    function convertHexStringToBytes32Array(string memory _hexString) public pure returns (bytes32[] memory) {
    //        bytes memory hexString = abi.encodePacked(_hexString);
    //        return abi.decode(hexString, (bytes32[]));
    //    }

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
