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
        vaultContract.initialize(address(vnft), _dao, 1);
        vm.prank(_dao);
        vaultContract.setLiquidStaking(address(liquidStaking));

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress);
        operatorRegistry.registerOperator{value: 0.1 ether}(
            "one", address(_rewardAddress), address(_controllerAddress), address(vaultContract)
        );
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
        vm.prank(address(20));
        vm.deal(address(20), 2 ether);
        liquidStaking.stakeETH{value: 1 ether}(_referral, 1);
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
}
