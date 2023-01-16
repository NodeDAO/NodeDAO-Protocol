// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import "../src/LiquidStaking.sol";
import "../src/oracles/BeaconOracle.sol";
import "../src/tokens/NETH.sol";
import "../src/registries/NodeOperatorRegistry.sol";

contract StakeETHTest is Test {
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
    address beaconOracleContractAdd;
    address validatorNftAdd;
    address validatorContractAdd;
    address nVNFTContractAddress;
    address depositContractAddress;
    LiquidStaking liqStakingContract;
    NodeOperatorRegistry nodeOperatorRegistry;
    BeaconOracle beaconOracle;
    NETH neth;

    function setUp() public {
        vm.warp(1673161943);
        liqStakingContract = new LiquidStaking();
        operatorAuthAdd = address(this);
        operatorDaoVaultAdd = address(998);
        operator1Add = address(1);
        nethAddress = address(2);
        referral = address(3);
        beaconOracleContractAdd = address(4);
        validatorNftAdd = address(5);
        validatorContractAdd = address(6);
        nVNFTContractAddress = address(7);
        depositContractAddress = address(8);
        nodeOperatorRegistry = new NodeOperatorRegistry();
        nodeOperatorRegistry.initialize(address(this), operatorDaoVaultAdd);
        nodeOperatorRegistry.registerOperator{value: 0.1 ether}(
            "operator1", operator1Add, operatorAuthAdd, validatorContractAdd
        );
        nodeOperatorRegistry.setTrustedOperator(1);
        (trusted, name, rewardAddress, controllerAddress, validatorContractAdd) =
            nodeOperatorRegistry.getNodeOperator(1, true);
    }

    function testStakeETH(uint256 stakeAmount) public {
        //correct test for stakeETH
        vm.assume(stakeAmount > 1000 wei);
        vm.assume(stakeAmount < 1000000 ether);
        beaconOracle = new BeaconOracle();
        beaconOracle.initialize(operatorAuthAdd);
        neth = new NETH();
        neth.setLiquidStaking(address(liqStakingContract));
        liqStakingContract.initialize(
            operatorAuthAdd,
            operatorDaoVaultAdd,
            withdrawalCreds,
            address(nodeOperatorRegistry),
            address(neth),
            nVNFTContractAddress,
            address(beaconOracle),
            depositContractAddress
        );

        liqStakingContract.setDaoAddress(operatorAuthAdd);
        liqStakingContract.setDepositFeeRate(0);

        liqStakingContract.stakeETH{value: 1 ether}(referral, 1);
        uint256 nEthValue1 = liqStakingContract.getNethOut(1e18);
        uint256 ethValue1 = liqStakingContract.getEthOut(1e18);
        console2.log("----ethValue1----", ethValue1);
        console2.log("----nEthValue1----", nEthValue1);

        liqStakingContract.stakeETH{value: 1 ether}(referral, 1);
        uint256 nEthValue2 = liqStakingContract.getNethOut(1e18);
        uint256 ethValue2 = liqStakingContract.getEthOut(1e18);
        console2.log("----ethValue2----", ethValue2);
        console2.log("----nEthValue2----", nEthValue2);

        liqStakingContract.stakeETH{value: 1 ether}(referral, 1);
        uint256 nEthValue3 = liqStakingContract.getNethOut(1e18);
        uint256 ethValue3 = liqStakingContract.getEthOut(1e18);
        console2.log("----ethValue3----", ethValue3);
        console2.log("----nEthValue3----", nEthValue3);
        // assertEq(ethValue, stakeAmount);
        // assertEq(liqStakingContract.getExchangeRate(), 1 ether);
        console.log(liqStakingContract.getExchangeRate());
    }

    // function testUnstakeETH(address _referral, uint256 amount) public { //correct test for unstakeETH
    //     vm.assume(amount > 1000 wei);
    //     vm.assume(amount < 1 ether);
    //     beaconOracle = new BeaconOracle();
    //     beaconOracle.initialize(operatorAuthAdd);
    //     neth = new NETH();
    //     neth.setLiquidStaking(address(liqStakingContract));
    //     liqStakingContract.initialize( operatorAuthAdd, operatorDaoVaultAdd, withdrawalCreds, address(nodeOperatorRegistry), address(neth), nVNFTContractAddress, address(beaconOracle), depositContractAddress );
    //     liqStakingContract.setDaoAddress(operatorAuthAdd);
    //     vm.prank(operator1Add) ;
    //     liqStakingContract.stakeETH{value: 31 ether }(referral, 1);
    //     vm.prank(operator1Add) ;
    //     liqStakingContract.unstakeETH(referral, amount);

    // }
}
