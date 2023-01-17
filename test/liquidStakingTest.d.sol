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
    event EthStake(address indexed from, uint256 amount, uint256 amountOut, address indexed _referral);
    event EthUnstake(address indexed from, uint256 amount, uint256 amountOut);
    event NftStake(address indexed from, uint256 count, address indexed _referral);
    event Eth32Deposit(bytes _pubkey, bytes _withdrawal, address _owner);
    event ValidatorRegistered(uint256 operator, uint256 tokenId);
    event NftWrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event NftUnwrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event OperatorClaimRewards(uint256 operatorId, uint256 rewards);
    event ClaimRewardsToUnstakePool(uint256 operatorId, uint256 rewards);
    event stakeETHToUnstakePool(uint256 operatorId, uint256 amount);
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

    function testStakeEthFailRequireCases() public {
        vm.expectRevert("Stake amount must be minimum  1000 wei");
        vm.prank(address(2));
        vm.deal(address(2), 12 ether);
        liquidStaking.stakeETH{value: 100 wei}(_referral, 1);

        vm.expectRevert("Referral address must be provided");
        vm.prank(address(2));
        liquidStaking.stakeETH{value: 1 ether }(address(0), 1);

        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(address(2));
        liquidStaking.stakeETH{value: 1 ether }(_referral, 3);  
    }

    function testStakeNFT() public {
        vm.expectEmit(true, true, false, true);
        emit NftStake(address(2), 1, _referral);
        vm.prank(address(2));
        vm.deal(address(2), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(_referral, 1);
    }

    function testStakeETH() public {
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        uint256 nethValue;
        nethValue = liquidStaking.getNethOut( 1 ether);

        vm.expectEmit(true, true, false, true);
        emit EthStake(address(15), 1 ether, nethValue , _referral );
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

    }

    // function testWrapNFTRequireCases() public {
    //     vm.expectRevert("The selected token id does not belong to the operator being sold");
    //     vm.prank(address(4));
    //     vm.deal(address(4), 32 ether); 
    //     bytes32[] memory proof1 ;
    //     proof1 ="0x212" ;
    //     liquidStaking.wrapNFT(3, proof1, 2);
    // }

}


