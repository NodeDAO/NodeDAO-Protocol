// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import "../src/LiquidStaking.sol";
import "../src/oracles/BeaconOracle.sol";
import "../src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/rewards/ELVault.sol";
import "src/mocks/DepositContract.sol";
import "../src/registries/NodeOperatorRegistry.sol";
import "src/rewards/ELVaultFactory.sol";

contract LiquidStakingTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event EthStake(address indexed from, uint256 amount, uint256 amountOut, address indexed _referral);
    event EthUnstake(address indexed from, uint256 amount, uint256 amountOut);
    event NftStake(address indexed from, uint256 count);
    event Eth32Deposit(bytes _pubkey, bytes _withdrawal, address _owner);
    event ValidatorRegistered(uint256 operator, uint256 tokenId);
    event NftWrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event NftUnwrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event OperatorClaimRewards(uint256 operatorId, uint256 rewards);
    event ClaimRewardsToUnstakePool(uint256 operatorId, uint256 rewards);
    event UserClaimRewards(uint256 operatorId, uint256 rewards);
    event Transferred(address _to, uint256 _amount);

    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    NodeOperatorRegistry operatorRegistry;
    BeaconOracle beaconOracle;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;

    address _dao = address(1);
    address _daoValutAddress = address(2);
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
    address _referral = address(5);
    address _oracleMember1 = address(11);
    address _oracleMember2 = address(12);
    address _oracleMember3 = address(13);
    address _oracleMember4 = address(14);
    address _oracleMember5 = address(15);
    bytes withdrawalCreds = hex"00e6959a366e85294d398057f19c6d413b2de2385119ab51298b8a25504f3de1";
    bytes tempSignature = hex"938eda26f3dbd003bde75195d82e5aa445827284f8961f1abf5da1b2f6b51b0f21eb9fe807e27bb593d22f4bc9d5498d068f2855087eab6ac7b099a0c8919b24e379ec253bdfe02a0c760f01a51a008f8487c2afe6e57f25953a3270d85511e3";
    bytes32 tempDepositDataRoot = hex"e8066e21802a6eb322aa4f8c2e53d432176b495ee08f6863170b2ed2f0b90953";
    bytes pubKey = hex"a1f4c80ae6751b7d4453e3f7260ebe2691fd863a826323f9770151cfc69375ab252b78367ca440663809661f1b1c6864";

    function setUp() public {
        liquidStaking = new LiquidStaking();

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();
        vaultContract.initialize(address(vnft), _dao, 1, address(liquidStaking));
        vm.prank(_dao);
        vaultContract.setLiquidStaking(address(liquidStaking));

        vaultFactoryContract = new ELVaultFactory();
        vaultFactoryContract.initialize(address(vaultContract), address(vnft), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress, address(vaultFactoryContract));
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(_rewardAddress), address(_controllerAddress));

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        depositContract = new DepositContract();

        vm.warp(1673161943);
        beaconOracle = new BeaconOracle();
        beaconOracle.initialize(_dao);

        vm.startPrank(_dao);
        beaconOracle.addOracleMember(_oracleMember1);
        beaconOracle.addOracleMember(_oracleMember2);
        beaconOracle.addOracleMember(_oracleMember3);
        beaconOracle.addOracleMember(_oracleMember4);
        beaconOracle.addOracleMember(_oracleMember5);
        vm.stopPrank();

        bytes32 root = 0xa934c462ec150e180a501144c494ec0d63878c1a9caca5b3d409787177c99798;
        vm.prank(_oracleMember1);
        beaconOracle.reportBeacon(147375, 123456789123456789, 12345, root);

        liquidStaking.initialize(
            _dao,
            _daoValutAddress,
            withdrawalCreds,
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(beaconOracle),
            address(depositContract)
        );
    }

    function testSetDaoAddress() public {
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_referral);
        assertEq(liquidStaking.dao(), _referral);
    }

    function testSetUnstakePoolSize(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setUnstakePoolSize(nethAmount);
        assertEq(liquidStaking.unstakePoolSize(), nethAmount);
    }

    function testFailSetDepositFeeRate(uint256 feeRate) public {
        vm.assume(feeRate > 10000);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(feeRate);
        failed();
    }

    function testSetDepositFeeRate(uint256 feeRate) public {
        vm.assume(feeRate < 10000);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(feeRate);
        assertEq(liquidStaking.depositFeeRate(), feeRate);
    }

    function testFailSetUnstakeFeeRate(uint256 feeRate) public {
        vm.assume(feeRate > 10000);
        vm.prank(_dao);
        liquidStaking.setUnstakeFeeRate(feeRate);
        failed();
    }

    function testSetUnstakeFeeRate(uint256 feeRate) public {
        vm.assume(feeRate < 10000);
        vm.prank(_dao);
        liquidStaking.setUnstakeFeeRate(feeRate);
        assertEq(liquidStaking.unstakeFeeRate(), feeRate);
    }

    function testGetEthOut(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        neth = new NETH();
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
        uint256 ethValue;
        ethValue = liquidStaking.getEthOut(nethAmount);
        assertEq(ethValue, nethAmount);
    }

    function testGetNethValue(uint256 ethAmount) public {
        vm.assume(ethAmount > 1000 wei);
        vm.assume(ethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        liquidStaking.stakeETH{value: (ethAmount)}(_referral, 1);
        uint256 nethValue;
        nethValue = liquidStaking.getNethOut(ethAmount);
        assertEq(nethValue, ethAmount);
    }

    function testGetExchangeRate(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(3000);
        liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
        uint256 ethValue;
        ethValue = liquidStaking.getExchangeRate();
        assertEq(ethValue, 1 ether);
    }

    function testStakeEthWithDiscount(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(3000);
        liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
        uint256 ethValue;
        uint256 calculatedValue;
        ethValue = liquidStaking.getTotalEthValue();
        calculatedValue = (nethAmount - ((nethAmount * 3000) / 10000));
        assertEq(ethValue, calculatedValue);
    }

    function testStakeNFT() public {
        vm.prank(address(2));
        vm.deal(address(2), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
    }

    function testUnstakeETH(uint256 ethAmount) public {
        address randomPerson = address(888);
        address randomRichPerson = address(887);
        vm.assume(ethAmount > 1000 wei);
        vm.assume(ethAmount < 1000000 ether);
        ethAmount = 10000 wei;
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(3000);
        uint256 currentNethBal = neth.balanceOf(randomPerson);
        vm.prank(randomPerson);
        vm.deal(randomPerson, ethAmount);
        liquidStaking.stakeETH{value: (ethAmount)}(_referral, 1);
        vm.prank(randomRichPerson);
        vm.deal(randomRichPerson, 10000000 ether);
        liquidStaking.stakeETH{value: (10000000 ether)}(_referral, 1);
        uint256 afterNethBal = neth.balanceOf(randomPerson);
        vm.prank(randomPerson);
        liquidStaking.unstakeETH(afterNethBal);
    }

    function testRegisterValidator() public {
        bytes[] memory localpk = new bytes[](1);
        bytes[] memory localSig = new bytes[](1);
        bytes32[] memory localDataRoot = new bytes32[](1);
        // address localAddress = 0xa1f4c80ae6751b7d4453e3f7260ebe2691fd863a826323f9770151cfc69375ab252b78367ca440663809661f1b1c6864; //  bytesToAddress(pubKey);
        // address(uint160(uint256(b)))
        localpk[0] = pubKey;
        localSig[0] = tempSignature;
        localDataRoot[0] = tempDepositDataRoot;
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        vm.prank(_rewardAddress);
        vm.deal(_rewardAddress, 1000000 ether);
        liquidStaking.stakeETH{value: 1000000 ether}(_referral, 1);
        vm.prank(_controllerAddress);
        liquidStaking.registerValidator(
            localpk,
            localSig,
            localDataRoot
        );
        
    }

    function testWrapNFT() public {
        vm.prank(address(2));
        vm.deal(address(2), 100 ether);
        // "0x3495a5c67a5ac9c051fcbdb9580b2e942561eaea51843c20cffa990145635a78"
        liquidStaking.stakeNFT{value: 64 ether}(_referral, 1);
        uint256[] memory tokenIds = vnft.tokensOfOwner(address(2));
        assertEq(vnft.ownerOf(0), address(2));
        assertEq(tokenIds.length, 2);
        console.logAddress(vnft.ownerOf(1));
        // bytes32[] memory proof;
        // bytes32 temp0 = hex"3495a5c67a5ac9c051fcbdb9580b2e942561eaea51843c20cffa990145635a78";
        // bytes32 temp1 = hex"2955d7769ed0eee83e6f49b40835537ec10bd3d50d2f9ca0122c5d105dfbf9ce";

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0x877794ba7ca53549ef847bec0cf7a76f50f7f2c3a192f8daf952583741b8580e;
        proof[1] = 0xab2e0accab37b2e656021ad27eb3c7b975672f09b9c5e94ec87e50acad3373ec;

        // proof = new bytes32[](2);
        // proof[0] = temp0;
        // proof[1] = temp1;
        for (uint256 index = 0; index < tokenIds.length; index++) {
            console.log("token:");
            console.log(index);
            console.log(tokenIds[index]);
        }

        // bytes[] memory localpk = new bytes[](1);
        // bytes[] memory localSig = new bytes[](1);
        // bytes32[] memory localDataRoot = new bytes32[](1);
        // // address localAddress = 0xa1f4c80ae6751b7d4453e3f7260ebe2691fd863a826323f9770151cfc69375ab252b78367ca440663809661f1b1c6864; //  bytesToAddress(pubKey);
        // // address(uint160(uint256(b)))
        // bytes memory pubkey =
        //     hex"80000001677f23a227dfed6f61b132d114be83b8ad0aa5f3c5d1d77e6ee0bf5f73b0af750cc34e8f2dae73c21dc36f4a";
        // localpk[0] = pubKey;
        // localSig[0] = tempSignature;
        // localDataRoot[0] = tempDepositDataRoot;
        // vm.prank(_dao);
        // liquidStaking.setDepositFeeRate(0);
        // vm.prank(_rewardAddress);
        // vm.deal(_rewardAddress, 1000000 ether);
        // liquidStaking.stakeETH{value: 1000000 ether}(_referral, 1);
        // vm.prank(_controllerAddress);
        // liquidStaking.registerValidator(
        //     localpk,
        //     localSig,
        //     localDataRoot
        // );
        // vm.prank(address(2));

        // liquidStaking.wrapNFT(tokenIds[1], proof, 32 ether);
    }

    // function testUnstakeETHWithDiscount(uint256 nethAmount) public {
    //     vm.assume(nethAmount > 1000 wei);
    //     vm.assume(nethAmount < 1000000 ether);
    //     liquidStaking.setDaoAddress(_dao);
    //     liquidStaking.setDepositFeeRate(3000);
    //     liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
    //     uint256[] memory operatorIds = new uint256[](1);
    //     liquidStaking.batchClaimRewardsOfOperator(operatorIds);
    //     // uint256 ethValue;
    //     uint256 calculatedValue;
    //     // ethValue = liquidStaking.getTotalEthValue();
    //     calculatedValue = (nethAmount - ((nethAmount * 3000) / 10000));
    //     liquidStaking.unstakeETH(calculatedValue);
    //     // assertEq(ethValue, calculatedValue);
    // }

    // function testMint(uint256 ethAmount) public {
    //     ExpectEmit emitter = new ExpectEmit();

    //     liquidStaking.initialize(
    //         withdrawalCreds, address(nodeOperatorRegistry), nethAddress, beaconOracleContractAdd, validatorNftAdd
    //     );
    //     liquidStaking.setDepositFeeRate(0);
    //     liquidStaking.stakeETH{value: 1000000 ether}(_referral, 0);
    //     neth = new NETH();
    //     vm.prank(address(1));
    //     neth.initialize(address(liquidStaking));

    //     vm.assume(ethAmount > 100 wei);
    //     vm.assume(ethAmount < 1000000 ether);
    //     uint256 nethValue;
    //     vm.expectEmit(true, false, true, false);
    //     emitter.mintEvent(operator1Add, nethValue, ethAmount, block.timestamp);
    //     nethValue = neth.mint(ethAmount, operator1Add);
    //     assertEq(nethValue, ethAmount);
    // }

    // function testBurn(uint256 ethAmount) public {
    //     ExpectEmit emitter = new ExpectEmit();

    //     liquidStaking.initialize(
    //         withdrawalCreds, address(nodeOperatorRegistry), nethAddress, beaconOracleContractAdd, validatorNftAdd
    //     );
    //     liquidStaking.setDepositFeeRate(0);
    //     liquidStaking.stakeETH{value: 1000000 ether}(_referral, 0);
    //     neth = new NETH();
    //     vm.prank(address(1));
    //     neth.initialize(address(liquidStaking));

    //     vm.assume(ethAmount > 100 wei);
    //     vm.assume(ethAmount < 1000000 ether);
    //     uint256 ethValue;
    //     uint256 nethValue;
    //     nethValue = neth.mint(ethAmount, operator1Add);
    //     vm.expectEmit(true, false, true, false);
    //     emitter.burnEvent(operator1Add, nethValue, ethAmount, block.timestamp);
    //     vm.prank(address(1));
    //     ethValue = neth.burn(nethValue);
    //     assertEq(nethValue, ethAmount);
    // }

    // DaoTreasuries.balanceOf() check if equal to deposit fee
}

// contract ExpectEmit {
//     event TokensMinted(address indexed to, uint256 amount, uint256 ethAmount, uint256 time);
//     event TokensBurned(address indexed from, uint256 amount, uint256 ethAmount, uint256 time);

//     function mintEvent(address _to, uint256 _amount, uint256 _ethAmount, uint256 _time) public {
//         emit TokensMinted(_to, _amount, _ethAmount, _time);
//     }

//     function burnEvent(address _from, uint256 _amount, uint256 _ethAmount, uint256 _time) public {
//         emit TokensBurned(_from, _amount, _ethAmount, _time);
//     }
// }
