// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import "../src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/rewards/ELVault.sol";
import "src/oracles/BeaconOracle.sol";
import "src/rewards/ELVaultFactory.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

contract LiquidStakingTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event EthStake(address indexed from, uint256 amount, uint256 amountOut, address indexed _referral);
    event EthUnstake(address indexed from, uint256 amount, uint256 amountOut);
    event NftStake(address indexed from, uint256 count, address indexed _referral);
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

    address _dao = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoValutAddress = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
    address _referral = address(5);
    address _oracleMember1 = address(11);
    address _oracleMember2 = address(12);
    address _oracleMember3 = address(13);
    address _oracleMember4 = address(14);
    address _oracleMember5 = address(15);
    bytes withdrawalCreds = hex"3031";
    address _rewardAddress2 = address(133);
    address _controllerAddress2 = address(144);

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
        operatorRegistry.registerOperator{value: 0.1 ether}("two", address(_rewardAddress2), address(_controllerAddress2));

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(2);

        depositContract = new DepositContract();

        vm.warp(1673161943);
        beaconOracle = new BeaconOracle();
        // goerli: 1616508000
        // mainnet: 1606824023
        uint64 genesisTime = 1616508000;
        beaconOracle.initialize(_dao, genesisTime);
        vm.startPrank(_dao);
        beaconOracle.addOracleMember(_oracleMember1);
        beaconOracle.addOracleMember(_oracleMember2);
        beaconOracle.addOracleMember(_oracleMember3);
        beaconOracle.addOracleMember(_oracleMember4);
        beaconOracle.addOracleMember(_oracleMember5);
        beaconOracle.setLiquidStaking(address(liquidStaking));
        vm.stopPrank();

        liquidStaking.initialize(
            _dao,
            _daoValutAddress,
            bytes("01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106"),
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(beaconOracle),
            address(depositContract)
        );
    }

    function testStakeEthFailRequireCases() public {
        vm.expectRevert("Stake amount must be minimum  1000 wei");
        vm.prank(address(2));
        vm.deal(address(2), 12 ether);
        liquidStaking.stakeETH{value: 100 wei}(_referral, 1);

        vm.expectRevert("Referral address must be provided");
        vm.prank(address(2));
        liquidStaking.stakeETH{value: 1 ether}(address(0), 1);

        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(address(2));
        liquidStaking.stakeETH{value: 1 ether}(_referral, 3);
    }

    function testStakeNFT2() public {
        vm.expectEmit(true, true, false, true);
        emit NftStake(address(23), 1, _referral);
        vm.prank(address(23));
        vm.deal(address(23), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        assertEq(1, vnft.balanceOf(address(23)));
    }

    function testStakeETH() public {
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        uint256 nethValue;
        nethValue = liquidStaking.getNethOut(1 ether);

        vm.expectEmit(true, true, false, true);
        emit EthStake(address(15), 1 ether, nethValue, _referral);
        vm.prank(address(15));
        vm.deal(address(15), 3 ether);
        liquidStaking.stakeETH{value: 1 ether}(_referral, 1);
    }

    function testStakeNFTFailRequireCases() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(address(4));
        vm.deal(address(4), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 4);
        failed();

        vm.expectRevert("Incorrect Ether amount provided");
        vm.prank(address(20));
        vm.deal(address(20), 32 ether);
        liquidStaking.stakeNFT{value: 1 ether}(_referral, 1);
        failed();

        vm.expectRevert("Incorrect Ether amount provided");
        vm.prank(address(20));
        vm.deal(address(20), 20 ether);
        liquidStaking.stakeNFT{value: 3 ether}(_referral, 1);
        failed();
    }

    function testClaimRewardsOfOperator() public {
        vm.prank(address(114));
        vm.deal(address(114), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        liquidStaking.reinvestRewardsOfOperator(1);
        assertEq(1, vnft.balanceOf(address(114)));

        vm.prank(address(255));
        vm.deal(address(255), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        liquidStaking.reinvestRewardsOfOperator(1);
        assertEq(1, vnft.balanceOf(address(255)));
        assertEq(0, neth.balanceOf(address(255)));

    }

    function testRegisterValidatorFailCases() public {
        prepRegisterValidator();
        bytes[] memory pubkeys = new bytes[](1);

        bytes[] memory signatures = new bytes[](1);

        bytes32[] memory depositDataRoots = new bytes32[](1);
        vm.prank(_dao);
        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106")
        );
        bytes memory pubkey =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");

        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);

        vm.prank(address(_controllerAddress));
        bytes[] memory pubkeys2 = new bytes[](5);
        bytes[] memory pubkeys3 = new bytes[](2);

        pubkeys2[0] = pubkey;

        pubkeys3[0] = pubkey;
        pubkeys3[1] = pubkey;

        vm.expectRevert("All parameter array's must have the same length.");
        liquidStaking.registerValidator(pubkeys2, signatures, depositDataRoots);
        vm.expectRevert("msg.sender must be the controllerAddress of the trusted operator");
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

        bytes[] memory signatures2 = new bytes[](5);
        bytes[] memory signatures3 = new bytes[](2);
        signatures2[0] = sign;
        signatures3[0] = sign;
        signatures3[1] = sign;

        bytes32[] memory depositDataRoots2 = new bytes32[](5);
        bytes32[] memory depositDataRoots3 = new bytes32[](2);
        depositDataRoots2[0] = root;
        depositDataRoots3[0] = root;
        depositDataRoots3[1] = root;

        vm.expectRevert("Insufficient balance");
        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys2, signatures2, depositDataRoots2);

        vm.expectRevert("Pub key already in used");
        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys3, signatures3, depositDataRoots3);
    }

    function prepRegisterValidator() private {
        vm.roll(2000);

        vm.deal(address(77), 21 ether);
        vm.prank(address(77));
        liquidStaking.stakeETH{value: 20 ether}(_referral, 1);
        assertEq(0, vnft.balanceOf(address(77)));
        assertEq(20 ether, neth.balanceOf(address(77)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(20 ether, liquidStaking.operatorPoolBalances(1));

        vm.deal(address(88), 32 ether);
        vm.prank(address(88));
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        assertEq(1, vnft.balanceOf(address(88)));
        assertEq(0, neth.balanceOf(address(88)));

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(32 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(52 ether, liquidStaking.operatorPoolBalances(1));

        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("operatorVaultAddr: ", operatorVaultAddr);
        console.log("operatorVaultImpl: ", address(vaultContract));

        vm.deal(address(operatorVaultAddr), 1 ether);
        vm.roll(5000);

        vm.deal(address(55), 32 ether);
        vm.prank(address(55));
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        assertEq(1, vnft.balanceOf(address(55)));
        assertEq(0, neth.balanceOf(address(55)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(84 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(address(21).balance, 0);
        assertEq(address(22).balance, 0);

        assertEq(84 ether, liquidStaking.operatorPoolBalances(1));
    }

    function testGetLiquidNfts() public {
        vm.prank(address(liquidStaking));
        vm.deal(address(liquidStaking), 66 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        assertEq(1, vnft.balanceOf( address(liquidStaking) ));
        assertEq(1, vnft.getNftCountsOfOperator(1));
        vm.prank(address(liquidStaking));
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 2);
        assertEq(1, vnft.getNftCountsOfOperator(2));
        assertEq(2, vnft.balanceOf( address(liquidStaking) ));
    }


    function testMiscFunction() public {
        liquidStaking.isPaused();
        vm.prank(_dao);
        liquidStaking.pause();
        vm.prank(_dao);
        liquidStaking.unpause();
    }

    function testRegisterValidatorCorrect() public {
        prepRegisterValidator();
        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        vm.prank(_dao);
        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106")
        );
        bytes memory pubkey =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(52 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        console.log("neth.balanceOf(address(liquidStaking): ", neth.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 0);
    }
}
