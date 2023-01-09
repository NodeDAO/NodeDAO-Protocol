// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
//import "forge-std/console.sol";
import "src/oracles/BeaconOracle.sol";
import "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
//import "src/registries/NodeOperatorRegistry.sol";

contract BeaconOracleTest is Test {
    //    event AddOracleMember(address oracleMember);
    //    event RemoveOracleMember(address oracleMember);
    //    event ResetExpectedEpochId(uint256 expectedEpochId);
    //    event ResetEpochsPerFrame(uint256 epochsPerFrame);
    //    event ReportBeacon(uint256 epochId, address oracleMember, uint256 sameReportCount);
    //    event ReportSuccess(uint256 epochId, uint32 sameReportCount, uint32 quorum);

    BeaconOracle beaconOracle;
    //    NodeOperatorRegistry operatorRegistry;
    address _dao = address(1);
    address _liquidStakingContract = address(2);
    address _nodeOperatorsContract = address(3);

    //    address _daoValutAddress = address(2);

    function initializer() private {
        //        operatorRegistry.initialize(_dao, _daoValutAddress);
        beaconOracle.initialize(_dao, _liquidStakingContract, _nodeOperatorsContract);
    }

    //    function registerOperator() private {
    //        operatorRegistry.registerOperator{value : 0.1 ether}("one", address(21), address(4));
    //        operatorRegistry.registerOperator{value : 0.1 ether}("two", address(22), address(4));
    //        operatorRegistry.registerOperator{value : 0.1 ether}("three", address(23), address(4));
    //        operatorRegistry.registerOperator{value : 0.1 ether}("four", address(24), address(4));
    //        operatorRegistry.registerOperator{value : 0.1 ether}("five", address(25), address(4));
    //        operatorRegistry.setTrustedOperator(0);
    //        operatorRegistry.setTrustedOperator(1);
    //        operatorRegistry.setTrustedOperator(2);
    //        operatorRegistry.setTrustedOperator(3);
    //        operatorRegistry.setTrustedOperator(4);
    //    }

    function setUp() public {
        vm.warp(1673161943);
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
        assertFalse(beaconOracle.isReportBeacon());
    }

    // todo 合约之间的测试调用
    function testReportBeacon() public {

        vm.startPrank(address(1));
        beaconOracle.addOracleMember(address(11));
        beaconOracle.addOracleMember(address(12));
        beaconOracle.addOracleMember(address(13));
        //        registerOperator();
        //        assertEq(beaconOracle.getQuorum(), 3);
        vm.stopPrank();
        beaconOracle.oracleMemberCount();


        assertEq(beaconOracle.beaconBalances(), 0);
        assertEq(beaconOracle.beaconActiveValidators(), 0);
        assertFalse(beaconOracle.isReportBeacon());

        bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;

        vm.startPrank(address(11));
        assertFalse(beaconOracle.isReportBeacon());
        beaconOracle.reportBeacon(172800, 123456789, 12345, root);
        assertEq(beaconOracle.isReportBeacon(), true);
        vm.stopPrank();

        vm.startPrank(address(12));
        beaconOracle.reportBeacon(172800, 123456789, 12345, root);
        assertEq(beaconOracle.isReportBeacon(), true);
        vm.stopPrank();

        vm.startPrank(address(13));
        beaconOracle.reportBeacon(172800, 123456789, 12345, root);
        vm.stopPrank();

        assertEq(beaconOracle.beaconBalances(), 123456789);
        assertEq(beaconOracle.beaconActiveValidators(), 12345);
        assertEq(beaconOracle.isQuorum(), true);

        vm.prank(address(11));
        assertFalse(beaconOracle.isReportBeacon());
        vm.prank(address(12));
        assertFalse(beaconOracle.isReportBeacon());
        vm.prank(address(13));
        assertFalse(beaconOracle.isReportBeacon());

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
        bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;
        bytes memory pubkey = hex"80000001677f23a227dfed6f61b132d114be83b8ad0aa5f3c5d1d77e6ee0bf5f73b0af750cc34e8f2dae73c21dc36f4a";
        uint256 validatorBalance = 32000000000000000000;
        uint256 nftTokenID = 1;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0x877794ba7ca53549ef847bec0cf7a76f50f7f2c3a192f8daf952583741b8580e;
        proof[1] = 0xab2e0accab37b2e656021ad27eb3c7b975672f09b9c5e94ec87e50acad3373ec;

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(pubkey, validatorBalance, nftTokenID))));
        assertEq(leaf, 0x10e799df87265a6e1c8b5d60ce37fbca4a02c93b5a6a9f5895eeb41a209620f6);

        bool isVerify = MerkleProof.verify(proof, root, leaf);
        assertEq(isVerify, true);
    }

}
