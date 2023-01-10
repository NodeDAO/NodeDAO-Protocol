// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import "../src/tokens/NETH.sol";
import "../src/LiquidStaking.sol";
import "../src/registries/NodeOperatorRegistry.sol";

contract NEthTest is Test {
    NETH public neth;
    // Create mock contracts for iLiqStaking and totalSupply
    address public owner;
    address public operator1Add;
    address public nethAddress;
    address public referral;
    address public operatorAuthAdd;
    address public operatorDaoVaultAdd;
    bytes public withdrawalCreds;
    bool trusted;
    string name;
    address rewardAddress;
    address controllerAddress;
    address oracleAdd;
    address validatorNftAdd;
    LiquidStaking liqStakingContract;
    NodeOperatorRegistry nodeOperatorRegistry;

    function setUp() public {
        vm.warp(1673161943);
        liqStakingContract = new LiquidStaking();
        withdrawalCreds = "0x3333";
        operatorAuthAdd = address(this);
        operatorDaoVaultAdd = address(998);
        operator1Add = address(1);
        nethAddress = address(2);
        referral = address(3);
        oracleAdd = address(4);
        validatorNftAdd = address(5);

        nodeOperatorRegistry = new NodeOperatorRegistry();
        nodeOperatorRegistry.initialize(address(this), operatorDaoVaultAdd);
        nodeOperatorRegistry.registerOperator{value: 1000000 ether}("operator1", operator1Add, operatorAuthAdd);
        nodeOperatorRegistry.setTrustedOperator(0);
        (trusted, name, rewardAddress, controllerAddress) = nodeOperatorRegistry.getNodeOperator(0, true);
    }

    function testGetEthValue(uint256 nethAmount) public {
        liqStakingContract.initialize(
            withdrawalCreds, address(nodeOperatorRegistry), nethAddress, oracleAdd, validatorNftAdd
        );
        liqStakingContract.setDepositFeeRate(0);
        liqStakingContract.stakeETH{value: 1000000 ether}(referral, 0);
        neth = new NETH();
        vm.prank(address(1));
        neth.initialize(address(liqStakingContract));

        vm.assume(nethAmount > 100 wei);
        vm.assume(nethAmount < 1000000 ether);
        uint256 ethValue;
        ethValue = neth.getEthValue(nethAmount);
        assertEq(ethValue, nethAmount);
    }

    function testGetEthValueWithNoSupply(uint256 nethAmount) public {
        liqStakingContract.initialize(
            withdrawalCreds, address(nodeOperatorRegistry), nethAddress, oracleAdd, validatorNftAdd
        );
        liqStakingContract.setDepositFeeRate(5);
        neth = new NETH();
        vm.prank(address(1));
        neth.initialize(address(liqStakingContract));

        vm.assume(nethAmount > 100 wei);
        vm.assume(nethAmount < 1000000 ether);
        uint256 ethValue;
        ethValue = neth.getEthValue(nethAmount);
        assertEq(ethValue, nethAmount);
    }

    function testGetNethValue(uint256 ethAmount) public {
        liqStakingContract.initialize(
            withdrawalCreds, address(nodeOperatorRegistry), nethAddress, oracleAdd, validatorNftAdd
        );
        liqStakingContract.setDepositFeeRate(0);
        liqStakingContract.stakeETH{value: 1000000 ether}(referral, 0);
        neth = new NETH();
        vm.prank(address(1));
        neth.initialize(address(liqStakingContract));

        vm.assume(ethAmount > 100 wei);
        vm.assume(ethAmount < 1000000 ether);
        uint256 nethValue;
        nethValue = neth.getNethValue(ethAmount);
        assertEq(nethValue, ethAmount);
    }

    function testMint(uint256 ethAmount) public {
        ExpectEmit emitter = new ExpectEmit();

        liqStakingContract.initialize(
            withdrawalCreds, address(nodeOperatorRegistry), nethAddress, oracleAdd, validatorNftAdd
        );
        liqStakingContract.setDepositFeeRate(0);
        liqStakingContract.stakeETH{value: 1000000 ether}(referral, 0);
        neth = new NETH();
        vm.prank(address(1));
        neth.initialize(address(liqStakingContract));

        vm.assume(ethAmount > 100 wei);
        vm.assume(ethAmount < 1000000 ether);
        uint256 nethValue;
        vm.expectEmit(true, false, true, false);
        emitter.mintEvent(operator1Add, nethValue, ethAmount, block.timestamp);
        nethValue = neth.mint(ethAmount, operator1Add);
        assertEq(nethValue, ethAmount);
    }

    function testBurn(uint256 ethAmount) public {
        ExpectEmit emitter = new ExpectEmit();

        liqStakingContract.initialize(
            withdrawalCreds, address(nodeOperatorRegistry), nethAddress, oracleAdd, validatorNftAdd
        );
        liqStakingContract.setDepositFeeRate(0);
        liqStakingContract.stakeETH{value: 1000000 ether}(referral, 0);
        neth = new NETH();
        vm.prank(address(1));
        neth.initialize(address(liqStakingContract));

        vm.assume(ethAmount > 100 wei);
        vm.assume(ethAmount < 1000000 ether);
        uint256 ethValue;
        uint256 nethValue;
        nethValue = neth.mint(ethAmount, operator1Add);
        vm.expectEmit(true, false, true, false);
        emitter.burnEvent(operator1Add, nethValue, ethAmount, block.timestamp);
        vm.prank(address(1));
        ethValue = neth.burn(nethValue);
        assertEq(nethValue, ethAmount);
    }

    // DaoTreasuries.balanceOf() check if equal to deposit fee
}

contract ExpectEmit {
    event TokensMinted(address indexed to, uint256 amount, uint256 ethAmount, uint256 time);
    event TokensBurned(address indexed from, uint256 amount, uint256 ethAmount, uint256 time);

    function mintEvent(address _to, uint256 _amount, uint256 _ethAmount, uint256 _time) public {
        emit TokensMinted(_to, _amount, _ethAmount, _time);
    }

    function burnEvent(address _from, uint256 _amount, uint256 _ethAmount, uint256 _time) public {
        emit TokensBurned(_from, _amount, _ethAmount, _time);
    }
}
