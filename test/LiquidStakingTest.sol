import "forge-std/Test.sol";
import "src/LiquidStaking.sol";
import "../src/tokens/NETH.sol";
import "../src/registries/NodeOperatorRegistry.sol";

pragma solidity ^0.8.7;

contract LiquidStakingTest is Test {
    event DepositReceived(address indexed from, uint256 amount, address indexed _referral);
    event ELRewardsReceived(uint256 balance);
    event EtherDeposited(address from, uint256 balance, uint256 height);

    NETH public neth;
    // Create mock contracts for iLiqStaking and totalSupply
    address public operator1Add = address(1);
    address public operator2Add = address(2);
    address public operator3Add = address(3);
    address public nethAddress = address(4);
    address public referral = address(5);
    address oracleAdd = address(6);
    address validatorNftAdd = address(7);
    address public operatorAuthAdd = address(this);
    address public operatorDaoVaultAdd = address(998);
    bytes public withdrawalCreds = "0x3333";
    bool trusted;
    string name;
    address rewardAddress;
    address controllerAddress;

    LiquidStaking liqStakingContract;
    NodeOperatorRegistry nodeOperatorRegistry;

    function setUp() public {
        vm.warp(1673161943);
        liqStakingContract = new LiquidStaking();
        liqStakingContract.initialize(withdrawalCreds, operator1Add, nethAddress, oracleAdd, validatorNftAdd);
        liqStakingContract.setDepositFeeRate(0);

        nodeOperatorRegistry = new NodeOperatorRegistry();
        nodeOperatorRegistry.initialize(address(this), operatorDaoVaultAdd);
        nodeOperatorRegistry.registerOperator{value: 0.1 ether}("operator1", operator1Add, operatorAuthAdd);
        nodeOperatorRegistry.setTrustedOperator(0);

        neth = new NETH();
        vm.prank(address(1));
        neth.initialize(address(liqStakingContract));
    }

    function correctStakeETH() public {
        liqStakingContract.stakeETH{value: 0.1 ether}(referral, 0);
        assertEq(address(liqStakingContract).balance, 0.1 ether);
        assertEq(liqStakingContract.checkOperatorBalance(0), 0.1 ether);
        assertEq(liqStakingContract.checkOperatorBalance(1), 0);
    }
}
