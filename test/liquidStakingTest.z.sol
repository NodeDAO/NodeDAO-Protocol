// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/rewards/ELVault.sol";
import "src/oracles/BeaconOracle.sol";
import "forge-std/console.sol";
import "src/rewards/ELVaultFactory.sol";

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

    function testStakeETH() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(20), 1 ether);
        emit EthStake(address(20), 1 ether, 1 ether, _referral);
        vm.deal(address(20), 2 ether);

        console.log("rate: 1", liquidStaking.getNethOut(1 ether));
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 1 ether}(_referral, 1);
        console.log("rate: 2", liquidStaking.getNethOut(1 ether));
        vm.deal(address(21), 2 ether);

        console.log("rate: 3 ", liquidStaking.getNethOut(1 ether));
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 1 ether}(_referral, 1);
        console.log("balance: 21", neth.balanceOf(address(21)));
        console.log("rate: 4 ", liquidStaking.getNethOut(1 ether));

        vm.deal(address(23), 5 ether);

        console.log("rate: 4 ", liquidStaking.getNethOut(3 ether));
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 3 ether}(_referral, 1);
        console.log("balance: 23", neth.balanceOf(address(23)));

        assertEq(liquidStaking.unstakePoolBalances(), 0.5 ether);
        assertEq(liquidStaking.operatorPoolBalances(1), 4.5 ether);
    }

    function testStakeETHWithDepositFee() public {
        vm.deal(address(20), 2 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 1 ether}(_referral, 1);
        console.log("rate: 2", liquidStaking.getNethOut(1 ether));
        vm.deal(address(21), 2 ether);

        console.log("rate: 3 ", liquidStaking.getNethOut(1 ether));
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 1 ether}(_referral, 1);
        console.log("balance: 21", neth.balanceOf(address(21)));
        console.log("rate: 4 ", liquidStaking.getNethOut(1 ether));

        vm.deal(address(23), 5 ether);

        console.log("rate: 4 ", liquidStaking.getNethOut(3 ether));
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 3 ether}(_referral, 1);
        console.log("balance: 23", neth.balanceOf(address(23)));

        assertEq(liquidStaking.unstakePoolBalances(), 0.5 ether);
        assertEq(liquidStaking.operatorPoolBalances(1), 4.5 ether);

        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(1000);

        vm.deal(address(24), 500 ether);
        liquidStaking.stakeETH{value: 500 ether}(_referral, 1);
    }

    function testStakeNFT() public {
        vm.expectEmit(true, true, false, true);
        emit NftStake(address(20), 10, _referral);
        vm.prank(address(20));
        vm.deal(address(20), 330 ether);
        vm.roll(10000);

        liquidStaking.stakeNFT{value: 320 ether}(_referral, 1);
        assertEq(10, vnft.balanceOf(address(20)));

        assertEq(vnft.operatorEmptyNftIndex(1), 0);

        assertEq(vnft.operatorEmptyNfts(1, 0), 0);
        assertEq(vnft.operatorEmptyNfts(1, 1), 1);
        assertEq(vnft.operatorEmptyNfts(1, 2), 2);
        assertEq(vnft.operatorEmptyNfts(1, 3), 3);
        assertEq(vnft.operatorEmptyNfts(1, 4), 4);
        assertEq(vnft.operatorEmptyNfts(1, 5), 5);
        assertEq(vnft.operatorEmptyNfts(1, 6), 6);
        assertEq(vnft.operatorEmptyNfts(1, 7), 7);
        assertEq(vnft.operatorEmptyNfts(1, 8), 8);
        assertEq(vnft.operatorEmptyNfts(1, 9), 9);

        uint256 operatorId;
        uint256 initHeight;
        bytes memory pubkey;
        (operatorId, initHeight, pubkey) = vnft.validators(0);

        assertEq(operatorId, 1);
        assertEq(pubkey, bytes(""));
        assertEq(initHeight, 10000);
    }

    function testStakeNFT2() public {
        vm.prank(address(20));
        vm.roll(10000);

        liquidStaking.stakeNFT{value: 0 ether}(_referral, 1);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(0, neth.balanceOf(address(liquidStaking)));
    }

    function testGetExchangeRate() public {
        vm.roll(10000);

        vm.prank(address(20));
        vm.deal(address(20), 330 ether);
        liquidStaking.stakeETH{value: 30 ether}(_referral, 1);

        vm.prank(address(21));
        vm.deal(address(21), 330 ether);
        liquidStaking.stakeETH{value: 31 ether}(_referral, 1);

        vm.prank(address(22));
        vm.deal(address(22), 330 ether);
        liquidStaking.stakeETH{value: 3.2 ether}(_referral, 1);

        vm.prank(address(23));
        vm.deal(address(23), 330 ether);
        liquidStaking.stakeETH{value: 0.32 ether}(_referral, 1);

        vm.prank(address(24));
        vm.deal(address(24), 330 ether);
        liquidStaking.stakeETH{value: 0.1457 ether}(_referral, 1);

        vm.prank(address(25));
        vm.deal(address(25), 330 ether);
        liquidStaking.stakeETH{value: 0.325878 ether}(_referral, 1);

        vm.prank(address(26));
        vm.deal(address(26), 330 ether);
        liquidStaking.stakeETH{value: 30.09987 ether}(_referral, 1);

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);

        vm.prank(address(20));
        liquidStaking.unstakeETH(0.00931 ether);

        vm.prank(address(21));
        liquidStaking.unstakeETH(0.131 ether);

        vm.prank(address(22));
        liquidStaking.unstakeETH(0.22231 ether);

        vm.prank(address(23));
        liquidStaking.unstakeETH(0.11112 ether);

        vm.prank(address(24));
        liquidStaking.unstakeETH(0.1011157 ether);

        vm.prank(address(25));
        liquidStaking.unstakeETH(0.11125878 ether);

        vm.prank(address(26));
        liquidStaking.unstakeETH(0.0003009987 ether);

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);
    }

    function testAll() public {
        vm.roll(10000);

        vm.deal(address(20), 33 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 32 ether}(_referral, 1);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(32 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(28.8 ether, liquidStaking.operatorPoolBalances(1));

        vm.deal(address(21), 32 ether);
        vm.prank(address(21));
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        assertEq(1, vnft.balanceOf(address(21)));
        assertEq(0, neth.balanceOf(address(21)));
        assertEq(3.2 ether, liquidStaking.unstakePoolBalances());
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(32 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(60.8 ether, liquidStaking.operatorPoolBalances(1));

        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("operatorVaultAddr: ", operatorVaultAddr);
        console.log("operatorVaultImpl: ", address(vaultContract));

        vm.deal(address(operatorVaultAddr), 1 ether);
        vm.roll(20000);

        vm.deal(address(22), 32 ether);
        vm.prank(address(22));
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
        assertEq(1, vnft.balanceOf(address(22)));
        assertEq(0, neth.balanceOf(address(22)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(92.8 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(address(21).balance, 0);
        assertEq(address(22).balance, 0);

        liquidStaking.claimRewardsOfUser(0);
        liquidStaking.claimRewardsOfUser(1);
        assertEq(address(22).balance, 0);
        assertEq(address(21).balance, 0.9 ether);
        assertEq(IELVault(operatorVaultAddr).getLiquidStakingReward(), 0);
        assertEq(3.2 ether, liquidStaking.unstakePoolBalances());

        assertEq(92.8 ether, liquidStaking.operatorPoolBalances(1));

        vm.deal(address(23), 33 ether);
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 32 ether}(_referral, 1);
        assertEq(0, vnft.balanceOf(address(23)));
        assertEq(32 ether, neth.balanceOf(address(23)));
        assertEq(6.4 ether, liquidStaking.unstakePoolBalances());
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(121.6 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);

        // unstakeETH
        vm.prank(address(23));
        liquidStaking.unstakeETH(1.1 ether);
        assertEq(30.9 ether, neth.balanceOf(address(23)));
        assertEq(5.3 ether, liquidStaking.unstakePoolBalances());
        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

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

        assertEq(89.6 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 0);

        vm.prank(_dao);
        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000d9e2dc13b0d2f6f73cd21c32fbf7de143c558e29")
        );
        pubkey =
            bytes(hex"83d3693fb9da8aed60a5c94c51927158d6e3a4d36fa6982ba2c87f83260329baf08f93d000f9261911420a9c0f0eb022");
        sign = bytes(
            hex"b0e13147956deb0b188e79de8181d0f9f216a43cf8fe0435c5c919da0182400e440ff6ba11d1c2ec12bec824200d9d07130d53260e8f03d7292af14e909731435ffe5beb4e97f7e97e55cd555e99e23de6dbb5618a40bd26b7537b9cd4104370"
        );
        root = bytes32(hex"f497234b67c6258b9cd46627adb7a88a26a5b48cbe90ee3bdb24bf9c559a0595");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 1);
        assertEq(57.6 ether, liquidStaking.operatorPoolBalances(1));

        // unwrapNFT todo
    }

    function testRegisterValidator() public {
        vm.roll(10000);

        vm.deal(address(20), 55 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 50 ether}(_referral, 1);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(50 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(45 ether, liquidStaking.operatorPoolBalances(1));

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
    }
}
