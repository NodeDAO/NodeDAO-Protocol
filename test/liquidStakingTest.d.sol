// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import "../src/LiquidStaking.sol";
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
            bytes(hex"001c1e94882d5f461636f3ac314986165027497c9a48a0f1bdaa9147fdd09470"),
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
        assertEq(address(liquidStaking).balance, 1 ether );
    }


        function testStakeNFT() public {
        bytes[] memory myBytesArray = new bytes[](1);
    
        bytes memory pubkey = bytes(hex"011c0000000000000000000000000000b0917fe7ef834819712d3bc5cbb37fb89b49a6149b573bf07f28059b6560d575ff09a44980bf9b0a37febc0a979b2a01001c1e94882d5f461636f3ac314986165027497c9a48a0f1bdaa9147fdd09470a9e48de9f5bf75fbc9847d2ffa51be36a8377cce0509f83a05bcb7b4507668d665d2e25309ed9880f57ba372b87c3e5817fb8ce289e0a22c655762145c0300d00afe9ebf83ccbd54e8110ad5980f67165fd26d290b9aa50f0f7c49619d587196b84839697afc4e347e943d9472abb000f37c0e61679fb31105d46340d0291aab0000000000000000000000000000000000000000000000000000000006e1752c7ac4d1706a72cf62bd12f89eceead45f07a5325010f3c11cbac71d6cca9c9ba7dc46f6f7bdeaa3fcaf011ad4891ad608ac9bbf5c1400d72df0358e81db53d7d7");
        bytes memory packedBytes = abi.encodePacked( pubkey );
        bytes memory operatorId = bytes(hex"0000000000000000000000000000000000000000000000000000000000000001");
        packedBytes = abi.encodePacked(packedBytes, operatorId);

        myBytesArray[0] = packedBytes;
        vm.prank(address(30)) ;
        vm.deal(address(30), 33 ether) ;
        vm.warp(1673161943);

        liquidStaking.stakeNFT{value: 32 ether}(myBytesArray);

    }


    // function testClaimRewards() public {
    //     vm.expectEmit(true, true, false, true);
    //     emit Transfer(address(0), address(20), 1 ether);
    //     emit EthStake(address(20), 1 ether, 1 ether, _referral);
    //     vm.prank(address(20));
    //     vm.deal(address(20), 2 ether);
    //     liquidStaking.stakeETH{value: 1 ether}(_referral, 1);
    //     assertEq(address(liquidStaking).balance, 1 ether );
    //     liquidStaking.claimRewardsOfOperator(1) ;
    // }


}
