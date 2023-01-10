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
    address public operator2Add;
    address public operator3Add;
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
        operator2Add = address(2);
        operator3Add = address(3);
        nethAddress = address(4);
        referral = address(5);
        oracleAdd = address(6);
        validatorNftAdd = address(7);

        nodeOperatorRegistry = new NodeOperatorRegistry();
        nodeOperatorRegistry.initialize(address(this), operatorDaoVaultAdd);
        nodeOperatorRegistry.registerOperator{value: 0.1 ether}("operator1", operator1Add, operatorAuthAdd);
        nodeOperatorRegistry.setTrustedOperator(0);
        (trusted, name, rewardAddress, controllerAddress) = nodeOperatorRegistry.getNodeOperator(0, true);

        // console.log(trusted);
        // console.log(name);
        // console.log(rewardAddress);
        // console.log(controllerAddress);
        (trusted, name, rewardAddress, controllerAddress) = nodeOperatorRegistry.getNodeOperator(0, true);

        console.log(trusted);
        console.log(name);
        console.log(rewardAddress);
        console.log(controllerAddress);

        // console.log("@@@@@@@");
        // console.log(nodeOperatorRegistry.isTrustedOperator(0));

        liqStakingContract.initialize(withdrawalCreds, operator1Add, nethAddress, oracleAdd, validatorNftAdd);
        liqStakingContract.setDepositFeeRate(0);
        liqStakingContract.stakeETH{value: 0.1 ether}(referral, 0);
        neth = new NETH();
        vm.prank(address(1));
        neth.initialize(address(liqStakingContract));
    }

    function testGetEthValue(uint256 nethAmount) public {
        vm.assume(nethAmount > 100 wei);
        vm.assume(nethAmount < 0.1 ether);
        uint256 ethValue;
        ethValue = neth.getEthValue(nethAmount);
        assertEq(ethValue, nethAmount);
    }

    function testGetNethValue(uint256 ethAmount) public {
        vm.assume(ethAmount > 100 wei);
        vm.assume(ethAmount < 0.1 ether);
        uint256 nethValue;
        nethValue = neth.getNethValue(ethAmount);
        assertEq(nethValue, ethAmount);
    }

    function testMint(uint256 ethAmount) public {
        vm.assume(ethAmount > 100 wei);
        vm.assume(ethAmount < 0.1 ether);
        uint256 nethValue;
        nethValue = neth.mint(ethAmount, operator1Add);
        assertEq(nethValue, ethAmount);
    }
}
