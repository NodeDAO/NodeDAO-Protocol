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

contract LiquidStakingTest is Test {
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
        withdrawalCreds = "0x3333";
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
        // console.log(trusted);
        // console.log(name);
        // console.log(rewardAddress);
        // console.log(controllerAddress);
        // console.log(validatorContractAdd);
    }

    // function testGetTotalEthValue() public {
    //     beaconOracle = new BeaconOracle();
    //     beaconOracle.initialize(operatorAuthAdd);
    //     liqStakingContract.initialize(
    //         operatorAuthAdd,
    //         operatorDaoVaultAdd,
    //         withdrawalCreds,
    //         address(nodeOperatorRegistry),
    //         nethAddress,
    //         nVNFTContractAddress,
    //         address(beaconOracle),
    //         depositContractAddress
    //     );
    //     liqStakingContract.setDaoAddress(operatorAuthAdd);
    //     uint256 totalEth = liqStakingContract.getTotalEthValue();
    //     assertEq(0, totalEth);
    // }

    // function testGetEthOut(uint256 nethAmount) public {
    //     vm.assume(nethAmount > 1000 wei);
    //     vm.assume(nethAmount < 1000000 ether);
    //     beaconOracle = new BeaconOracle();
    //     beaconOracle.initialize(operatorAuthAdd);
    //     neth = new NETH();
    //     neth.setLiquidStaking(address(liqStakingContract));
    //     liqStakingContract.initialize(
    //         operatorAuthAdd,
    //         operatorDaoVaultAdd,
    //         withdrawalCreds,
    //         address(nodeOperatorRegistry),
    //         address(neth),
    //         nVNFTContractAddress,
    //         address(beaconOracle),
    //         depositContractAddress
    //     );
    //     liqStakingContract.setDaoAddress(operatorAuthAdd);
    //     liqStakingContract.setDepositFeeRate(0);
    //     liqStakingContract.stakeETH{value: (nethAmount)}(referral, 1);
    //     uint256 ethValue;
    //     ethValue = liqStakingContract.getEthOut(nethAmount);
    //     assertEq(ethValue, nethAmount);
    // }

    // function testStakeEthWithDiscount(uint256 nethAmount) public {
    //     vm.assume(nethAmount > 1000 wei);
    //     vm.assume(nethAmount < 1000000 ether);
    //     beaconOracle = new BeaconOracle();
    //     beaconOracle.initialize(operatorAuthAdd);
    //     neth = new NETH();
    //     neth.setLiquidStaking(address(liqStakingContract));
    //     liqStakingContract.initialize(
    //         operatorAuthAdd,
    //         operatorDaoVaultAdd,
    //         withdrawalCreds,
    //         address(nodeOperatorRegistry),
    //         address(neth),
    //         nVNFTContractAddress,
    //         address(beaconOracle),
    //         depositContractAddress
    //     );
    //     liqStakingContract.setDaoAddress(operatorAuthAdd);
    //     liqStakingContract.setDepositFeeRate(3000);
    //     liqStakingContract.stakeETH{value: (nethAmount)}(referral, 1);
    //     uint256 ethValue;
    //     uint256 calculatedValue;
    //     ethValue = liqStakingContract.getTotalEthValue();
    //     calculatedValue = (nethAmount - ((nethAmount * 3000) / 10000));
    //     assertEq(ethValue, calculatedValue);
    // }

    // function testGetNethValue(uint256 ethAmount) public {
    //     vm.assume(ethAmount > 1000 wei);
    //     vm.assume(ethAmount < 1000000 ether);
    //     beaconOracle = new BeaconOracle();
    //     beaconOracle.initialize(operatorAuthAdd);
    //     neth = new NETH();
    //     neth.setLiquidStaking(address(liqStakingContract));
    //     liqStakingContract.initialize(
    //         operatorAuthAdd,
    //         operatorDaoVaultAdd,
    //         withdrawalCreds,
    //         address(nodeOperatorRegistry),
    //         address(neth),
    //         nVNFTContractAddress,
    //         address(beaconOracle),
    //         depositContractAddress
    //     );
    //     liqStakingContract.setDaoAddress(operatorAuthAdd);
    //     liqStakingContract.setDepositFeeRate(0);
    //     liqStakingContract.stakeETH{value: (ethAmount)}(referral, 1);
    //     uint256 nethValue;
    //     nethValue = liqStakingContract.getNethOut(ethAmount);
    //     console.log(nethValue);
    //     console.log(ethAmount);
    //     assertEq(nethValue, ethAmount);
    // }

    // function testGetExchangeRate(uint256 nethAmount) public {
    //     vm.assume(nethAmount > 1000 wei);
    //     vm.assume(nethAmount < 1000000 ether);
    //     beaconOracle = new BeaconOracle();
    //     beaconOracle.initialize(operatorAuthAdd);
    //     neth = new NETH();
    //     neth.setLiquidStaking(address(liqStakingContract));
    //     liqStakingContract.initialize(
    //         operatorAuthAdd,
    //         operatorDaoVaultAdd,
    //         withdrawalCreds,
    //         address(nodeOperatorRegistry),
    //         address(neth),
    //         nVNFTContractAddress,
    //         address(beaconOracle),
    //         depositContractAddress
    //     );
    //     liqStakingContract.setDaoAddress(operatorAuthAdd);
    //     liqStakingContract.setDepositFeeRate(3000);
    //     liqStakingContract.stakeETH{value: (nethAmount)}(referral, 1);
    //     uint256 ethValue;
    //     ethValue = liqStakingContract.getExchangeRate();
    //     assertEq(ethValue, 1 ether);
    // }


    function testUnstakeETHWithDiscount(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
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
        liqStakingContract.setDepositFeeRate(3000);
        liqStakingContract.stakeETH{value: (nethAmount)}(referral, 1);
        uint256[] memory operatorIds = new uint256[](1);
        liqStakingContract.batchClaimRewardsOfOperator(operatorIds);
        // uint256 ethValue;
        uint256 calculatedValue;
        // ethValue = liqStakingContract.getTotalEthValue();
        calculatedValue = (nethAmount - ((nethAmount * 3000) / 10000));
        liqStakingContract.unstakeETH(calculatedValue);
        // assertEq(ethValue, calculatedValue);
    }

    // function testMint(uint256 ethAmount) public {
    //     ExpectEmit emitter = new ExpectEmit();

    //     liqStakingContract.initialize(
    //         withdrawalCreds, address(nodeOperatorRegistry), nethAddress, beaconOracleContractAdd, validatorNftAdd
    //     );
    //     liqStakingContract.setDepositFeeRate(0);
    //     liqStakingContract.stakeETH{value: 1000000 ether}(referral, 0);
    //     neth = new NETH();
    //     vm.prank(address(1));
    //     neth.initialize(address(liqStakingContract));

    //     vm.assume(ethAmount > 100 wei);
    //     vm.assume(ethAmount < 1000000 ether);
    //     uint256 nethValue;
    //     vm.expectEmit(true, false, true, false);
    //     emitter.mintEvent(operator1Add, nethValue, ethAmount, block.timestamp);
    //     nethValue = neth.mint(ethAmount, operator1Add);
    //     assertEq(nethValue, ethAmount);
    // }

    // function testBurn(uint256 ethAmount) public {
    //     ExpectEmit emitter = new ExpectEmit();

    //     liqStakingContract.initialize(
    //         withdrawalCreds, address(nodeOperatorRegistry), nethAddress, beaconOracleContractAdd, validatorNftAdd
    //     );
    //     liqStakingContract.setDepositFeeRate(0);
    //     liqStakingContract.stakeETH{value: 1000000 ether}(referral, 0);
    //     neth = new NETH();
    //     vm.prank(address(1));
    //     neth.initialize(address(liqStakingContract));

    //     vm.assume(ethAmount > 100 wei);
    //     vm.assume(ethAmount < 1000000 ether);
    //     uint256 ethValue;
    //     uint256 nethValue;
    //     nethValue = neth.mint(ethAmount, operator1Add);
    //     vm.expectEmit(true, false, true, false);
    //     emitter.burnEvent(operator1Add, nethValue, ethAmount, block.timestamp);
    //     vm.prank(address(1));
    //     ethValue = neth.burn(nethValue);
    //     assertEq(nethValue, ethAmount);
    // }

    // DaoTreasuries.balanceOf() check if equal to deposit fee
}

// contract ExpectEmit {
//     event TokensMinted(address indexed to, uint256 amount, uint256 ethAmount, uint256 time);
//     event TokensBurned(address indexed from, uint256 amount, uint256 ethAmount, uint256 time);

//     function mintEvent(address _to, uint256 _amount, uint256 _ethAmount, uint256 _time) public {
//         emit TokensMinted(_to, _amount, _ethAmount, _time);
//     }

//     function burnEvent(address _from, uint256 _amount, uint256 _ethAmount, uint256 _time) public {
//         emit TokensBurned(_from, _amount, _ethAmount, _time);
//     }
// }
