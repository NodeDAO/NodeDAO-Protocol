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

    function testStakeEthFail() public {
        vm.prank(address(2));
        vm.deal(address(2), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
    }

    function testStakeNFT() public {
        vm.prank(address(2));
        vm.deal(address(2), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
    }

    function testStakeNFTFailNodeOperator() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(address(4));
        vm.deal(address(4), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 4);
        failed();
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

}


