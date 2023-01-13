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
    bytes  withdrawalCreds = hex"3031";

    function setUp() public {
        liquidStaking = new LiquidStaking();

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();
        vaultContract.initialize(address(vnft), _dao, 1);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress);
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(_rewardAddress), address(_controllerAddress), address(vaultContract));
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

    function testSetDaoAddress() public {
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_referral);
        assertEq(liquidStaking.dao(), _referral);
    }

    function testSetUnstakePoolSize(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setUnstakePoolSize(nethAmount);
        assertEq(liquidStaking.unstakePoolSize(), nethAmount);
    }

    function testFailSetDepositFeeRate(uint256 feeRate) public {
        vm.assume(feeRate > 10000);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(feeRate);
        failed();
    }

    function testSetDepositFeeRate(uint256 feeRate) public {
        vm.assume(feeRate < 10000);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(feeRate);
        assertEq(liquidStaking.depositFeeRate(), feeRate);
    }

    function testFailSetUnstakeFeeRate(uint256 feeRate) public {
        vm.assume(feeRate > 10000);
        vm.prank(_dao);
        liquidStaking.setUnstakeFeeRate(feeRate);
        failed();
    }

    function testSetUnstakeFeeRate(uint256 feeRate) public {
        vm.assume(feeRate < 10000);
        vm.prank(_dao);
        liquidStaking.setUnstakeFeeRate(feeRate);
        assertEq(liquidStaking.unstakeFeeRate(), feeRate);
    }

    function testGetEthOut(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        neth = new NETH();
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
        uint256 ethValue;
        ethValue = liquidStaking.getEthOut(nethAmount);
        assertEq(ethValue, nethAmount);
    }

    function testGetNethValue(uint256 ethAmount) public {
        vm.assume(ethAmount > 1000 wei);
        vm.assume(ethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        liquidStaking.stakeETH{value: (ethAmount)}(_referral, 1);
        uint256 nethValue;
        nethValue = liquidStaking.getNethOut(ethAmount);
        assertEq(nethValue, ethAmount);
    }

    function testGetExchangeRate(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(3000);
        liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
        uint256 ethValue;
        ethValue = liquidStaking.getExchangeRate();
        assertEq(ethValue, 1 ether);
    }

    function testStakeEthWithDiscount(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 wei);
        vm.assume(nethAmount < 1000000 ether);
        vm.prank(_dao);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(3000);
        liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
        uint256 ethValue;
        uint256 calculatedValue;
        ethValue = liquidStaking.getTotalEthValue();
        calculatedValue = (nethAmount - ((nethAmount * 3000) / 10000));
        assertEq(ethValue, calculatedValue);
    }

    function testStakeNFT() public {
        // vm.assume(bytesArr.length == 11);
        // bytes memory tempBytes;
        // for (uint256 index = 0; index < bytesArr.length; index++) {
        //     tempBytes = bytes.concat(bytes(tempBytes), " ", bytes(bytesArr[index]));
        // }

        bytes[] memory myBytesArray = new bytes[](4);
        bytes memory pubkey = bytes(hex"97b92f678f7c5f79c1b64844c639ccc12b8c6ff196a06d7db5969a889309bbe15d3a9befdb3fd8e97eb65084876d64de");
        bytes memory withdrawal_credentials = bytes(hex"004f58172d06b6d54c015d688511ad5656450933aff85dac123cd09410a0825c");
        bytes memory signature = bytes(hex"81037db57034ff28a8a703ba2f79af3edbd4766e732d4d51c89acc28094bc761a5cbed5317c0d4bb0a37d82a560d215e0f9097508914ae12fbd0258b6938e2b2d5d4daff91ea2b715c5b64f3d0bbda60321a4aacb9afe7034c567193705f82ad");
        bytes memory deposit_data_root = bytes(hex"7559c8495faab971d962d7a257ca37a4ba6fb69832fb1b3cbd12a805a51298c7");

        myBytesArray[0] = pubkey;
        myBytesArray[1] = withdrawal_credentials;
        myBytesArray[2] = signature;
        myBytesArray[3] = deposit_data_root;

        liquidStaking.stakeNFT(myBytesArray);

        // bytes memory operatorRegistryContractAddBytes = bytes(hex"72c1c4f08De52a2cEe82CE80D938c54b3B1df42e");

        // bytes memory nETHContractAddressBytes = bytes(hex"000B92c8CDB2b494D436ac13B43393bE8c4407C8");
        // bytes memory nVNFTContractAddressBytes = bytes(hex"d4A5DFd86BC22BDe059b7f2CBC1ebDE32F571e81");
        // bytes memory beaconOracleContractAddressBytes = bytes(hex"4375f0F6311777a720666e2F2E426Aeb9eEDC7fC");
        // bytes memory depositContractAddress = bytes(hex"ff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b");

        // liquidStaking.stakeNFT();

        // tempBytes = bytes.concat(bytes(tempBytes), " ", bytes(_rewardAddress));

        // console.log(tempBytes);

        // vm.prank(_dao);
        // liquidStaking.setDaoAddress(_dao);
        // vm.prank(_dao);
        // liquidStaking.setDepositFeeRate(3000);
        // liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
        // uint256 ethValue;
        // uint256 calculatedValue;
        // ethValue = liquidStaking.getTotalEthValue();
        // calculatedValue = (nethAmount - ((nethAmount * 3000) / 10000));
        // assertEq(ethValue, calculatedValue);
    }

    // function testUnstakeETHWithDiscount(uint256 nethAmount) public {
    //     vm.assume(nethAmount > 1000 wei);
    //     vm.assume(nethAmount < 1000000 ether);
    //     liquidStaking.setDaoAddress(_dao);
    //     liquidStaking.setDepositFeeRate(3000);
    //     liquidStaking.stakeETH{value: (nethAmount)}(_referral, 1);
    //     uint256[] memory operatorIds = new uint256[](1);
    //     liquidStaking.batchClaimRewardsOfOperator(operatorIds);
    //     // uint256 ethValue;
    //     uint256 calculatedValue;
    //     // ethValue = liquidStaking.getTotalEthValue();
    //     calculatedValue = (nethAmount - ((nethAmount * 3000) / 10000));
    //     liquidStaking.unstakeETH(calculatedValue);
    //     // assertEq(ethValue, calculatedValue);
    // }

    // function testMint(uint256 ethAmount) public {
    //     ExpectEmit emitter = new ExpectEmit();

    //     liquidStaking.initialize(
    //         withdrawalCreds, address(nodeOperatorRegistry), nethAddress, beaconOracleContractAdd, validatorNftAdd
    //     );
    //     liquidStaking.setDepositFeeRate(0);
    //     liquidStaking.stakeETH{value: 1000000 ether}(_referral, 0);
    //     neth = new NETH();
    //     vm.prank(address(1));
    //     neth.initialize(address(liquidStaking));

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

    //     liquidStaking.initialize(
    //         withdrawalCreds, address(nodeOperatorRegistry), nethAddress, beaconOracleContractAdd, validatorNftAdd
    //     );
    //     liquidStaking.setDepositFeeRate(0);
    //     liquidStaking.stakeETH{value: 1000000 ether}(_referral, 0);
    //     neth = new NETH();
    //     vm.prank(address(1));
    //     neth.initialize(address(liquidStaking));

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
