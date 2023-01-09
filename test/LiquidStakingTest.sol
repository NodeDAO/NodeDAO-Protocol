import "forge-std/Test.sol";
import "src/LiquidStaking.sol";

pragma solidity ^0.8.7;
contract LiquidStakingTest is Test {
    event DepositReceived(address indexed from, uint256 amount, address indexed _referral);
    event ELRewardsReceived(uint256 balance);
    event EtherDeposited(address from, uint256 balance, uint256 height);

    LiquidStaking liqStaking;


    // address _nethContract = address(1);
    // address _liquidStakingContract = address(2);
    // address _nodeOperatorsContract = address(3);
    // address _referral1 = address(4);
    // address _referral2 = address(0);

    // bytes  withdrawalCreds = "0x010000000000000000000000d530d401d03348e2b1364a4d586b75dcb2ed53fc";

    // function initializer() private {
    //     liqStaking.initialize(withdrawalCreds, _nodeOperatorsContract, _nethContract, address(1333));
    // }

    // function setUp() public {
    //     liqStaking = new LiquidStaking();
    //     initializer();
    // }

    // function testStakeETH2() public {//check for zero msg.value
    //     vm.prank(address(1));
    //     vm.expectRevert("Stake amount must not be Zero");
    //     liqStaking.stakeETH(_referral1, 12);
    // }

}
