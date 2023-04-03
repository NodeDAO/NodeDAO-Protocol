// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.7;

// import "forge-std/Test.sol";
// import "src/oracles/BeaconOracle.sol";
// import "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
// import "src/oracles/ReportUtils.sol";
// import "src/tokens/VNFT.sol";

// contract BeaconOracleTest is Test {
//     using ReportUtils for bytes;

//     BeaconOracle beaconOracle;
//     VNFT vnft;

//     address _dao = address(1);

//     function setUp() public {
//         vm.warp(1673161943);
//         beaconOracle = new BeaconOracle();

//         vnft = new VNFT();
//         vnft.initialize();
//         vnft.setLiquidStaking(address(1));
//         vm.startPrank(address(1));
//         vnft.whiteListMint(bytes("1"), address(2), 1);
//         vnft.whiteListMint(bytes("2"), address(2), 1);
//         vm.stopPrank();

//         // goerli: 1616508000
//         // mainnet: 1606824023
//         uint64 genesisTime = 1616508000;
//         beaconOracle.initialize(_dao, genesisTime, address(vnft));

//         vm.startPrank(_dao);
//         beaconOracle.addOracleMember(address(11));
//         beaconOracle.addOracleMember(address(12));
//         beaconOracle.addOracleMember(address(13));
//         beaconOracle.addOracleMember(address(14));
//         beaconOracle.addOracleMember(address(15));
//         vm.stopPrank();
//     }

//     function testDao() public {
//         assertEq(beaconOracle.dao(), _dao);
//     }

//     function testAddOracleMember() public {
//         vm.startPrank(address(1));

//         beaconOracle.addOracleMember(address(20));
//         beaconOracle.addOracleMember(address(21));
//         beaconOracle.addOracleMember(address(22));
//         beaconOracle.addOracleMember(address(23));

//         assertEq(beaconOracle.oracleMemberCount(), 9);

//         beaconOracle.removeOracleMember(address(21));
//         assertEq(beaconOracle.oracleMemberCount(), 8);

//         beaconOracle.addOracleMember(address(25));
//         assertEq(beaconOracle.getMemberId(address(25)), 6);
//         assertEq(beaconOracle.oracleMemberCount(), 9);

//         vm.stopPrank();
//     }

//     function testFailAuthOracleMember() public {
//         beaconOracle.addOracleMember(address(0x1234567812345678123456781234567812345678));
//         vm.expectRevert("PERMISSION_DENIED");
//     }

//     function testIsOracleMember() public {
//         testAddOracleMember();
//         bool isOracleMember = beaconOracle.isOracleMember(address(20));
//         assertEq(isOracleMember, true);
//     }

//     function testRemoveOracleMember() public {
//         vm.prank(address(1));

//         address _member = address(0x1234567812345678123456781234567812345678);

//         beaconOracle.addOracleMember(_member);
//         assertEq(beaconOracle.isOracleMember(_member), true);
//         vm.prank(address(1));
//         beaconOracle.removeOracleMember(_member);
//         assertEq(beaconOracle.isOracleMember(_member), false);
//     }

//     function testGetQuorum() public {
//         uint256 quorum = beaconOracle.getQuorum();
//         assertEq(quorum, 4);
//     }

//     function testGetConfig() public {
//         console.log(beaconOracle.expectedEpochId());
//         console.log(beaconOracle.genesisTime());
//         assertEq(beaconOracle.epochsPerFrame(), 225);
//         assertEq(beaconOracle.isCurrentFrame(), true);
//     }

//     function testResetEpochsPerFrame() public {
//         vm.prank(_dao);
//         beaconOracle.resetEpochsPerFrame(450);
//         assertEq(beaconOracle.epochsPerFrame(), 450);
//     }

//     function testReportBeacon() public {
//         assertEq(beaconOracle.beaconBalances(), 0);
//         assertEq(beaconOracle.beaconValidators(), 0);

//         bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;

//         vm.startPrank(address(11));
//         assertFalse(beaconOracle.isReportBeacon(address(11)));
//         beaconOracle.reportBeacon(147375, 64000000000000000000, 2, root);
//         assertEq(beaconOracle.isReportBeacon(address(11)), true);
//         vm.stopPrank();

//         vm.startPrank(address(12));
//         beaconOracle.reportBeacon(147375, 64000000000000000000, 2, root);
//         assertEq(beaconOracle.isReportBeacon(address(12)), true);
//         vm.stopPrank();

//         vm.startPrank(address(13));
//         beaconOracle.reportBeacon(147375, 64000000000000000000, 2, root);
//         vm.stopPrank();

//         vm.startPrank(address(14));
//         beaconOracle.reportBeacon(147375, 64000000000000000000, 2, root);
//         assertEq(beaconOracle.isReportBeacon(address(14)), false);
//         vm.stopPrank();

//         if (beaconOracle.isCurrentFrame()) {
//             vm.startPrank(address(15));
//             beaconOracle.reportBeacon(147375, 64000000000000000000, 2, root);
//             assertEq(beaconOracle.isReportBeacon(address(15)), false);
//             vm.stopPrank();
//         }

//         vm.startPrank(address(11));
//         assertFalse(beaconOracle.isReportBeacon(address(11)));
//         if (beaconOracle.isCurrentFrame()) {
//             beaconOracle.reportBeacon(147375, 64000000000000000000, 2, root);
//             assertEq(beaconOracle.isReportBeacon(address(11)), true);
//         }
//         vm.stopPrank();

//         assertEq(beaconOracle.beaconBalances(), 64000000000000000000);
//         assertEq(beaconOracle.getBeaconBalances(), 64000000000000000000);
//         assertEq(beaconOracle.beaconValidators(), 2);
//         assertEq(beaconOracle.getBeaconValidators(), 2);
//         assertEq(beaconOracle.isCurrentFrame(), false);

//         vm.prank(address(11));
//         assertFalse(beaconOracle.isReportBeacon(address(11)));
//         vm.prank(address(12));
//         assertFalse(beaconOracle.isReportBeacon(address(12)));
//         vm.prank(address(13));
//         assertFalse(beaconOracle.isReportBeacon(address(13)));
//     }

//     function testMerkle() public {
//         bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;
//         bytes32 leaf = 0x10e799df87265a6e1c8b5d60ce37fbca4a02c93b5a6a9f5895eeb41a209620f6;

//         bytes32[] memory proof = new bytes32[](2);
//         proof[0] = 0x877794ba7ca53549ef847bec0cf7a76f50f7f2c3a192f8daf952583741b8580e;
//         proof[1] = 0xab2e0accab37b2e656021ad27eb3c7b975672f09b9c5e94ec87e50acad3373ec;

//         bool isVerify = MerkleProof.verify(proof, root, leaf);
//         assertEq(isVerify, true);
//     }

//     function testVerifyNftValue() public {
//         bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;
//         bytes memory pubkey =
//             hex"80000001677f23a227dfed6f61b132d114be83b8ad0aa5f3c5d1d77e6ee0bf5f73b0af750cc34e8f2dae73c21dc36f4a";
//         uint256 validatorBalance = 32000000000000000000;
//         uint256 nftTokenID = 1;

//         bytes32[] memory proof = new bytes32[](2);
//         proof[0] = 0x877794ba7ca53549ef847bec0cf7a76f50f7f2c3a192f8daf952583741b8580e;
//         proof[1] = 0xab2e0accab37b2e656021ad27eb3c7b975672f09b9c5e94ec87e50acad3373ec;

//         bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(pubkey, validatorBalance, nftTokenID))));
//         assertEq(leaf, 0x10e799df87265a6e1c8b5d60ce37fbca4a02c93b5a6a9f5895eeb41a209620f6);

//         bool isVerify = MerkleProof.verify(proof, root, leaf);
//         assertEq(isVerify, true);
//     }

//     function compressData(bytes32 b32, uint256 u256) public pure returns (bytes memory) {
//         return abi.encodePacked(b32, u256);
//     }

//     function decompressData(bytes memory data) public pure returns (bytes32, uint256) {
//         (bytes32 b32, uint256 u256) = abi.decode(data, (bytes32, uint256));
//         return (b32, u256);
//     }

//     function testToBytes() public {
//         bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;
//         uint256 u = 12345;
//         bytes memory data = compressData(root, u);
//         (bytes32 rootRes, uint256 uRes) = decompressData(data);
//         assertEq(rootRes, root);
//         assertEq(uRes, u);

//         assertEq(
//             keccak256("oracle.reportsBitMask"), hex"c25c9b62b6d0f24f0d2ed8730d23f158f481aba9a9521a1d67014c7fa19a1ccd"
//         );
//     }
// }
