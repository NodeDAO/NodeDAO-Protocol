// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/vault/ELVault.sol";
import "src/vault/VaultManager.sol";
import "src/oracles/WithdrawOracle.sol";
import "forge-std/console.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/ConsensusVault.sol";
import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockOracleProvider.sol";
import "test/helpers/oracles/WithdrawOracleWithTimer.sol";
import "test/helpers/CommonConstantProvider.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";


contract LiquidStakingTest is Test, MockOracleProvider {

    event OperatorWithdraw(uint256 operatorId, uint256 withdrawAmount, address to);
    event BlacklistOperatorAssigned(uint256 indexed _blacklistOperatorId, uint256 _operatorId, uint256 _totalAmount);
    event QuitOperatorAssigned(uint256 indexed _quitOperatorId, uint256 _operatorId, uint256 _totalAmount);
    event EthStake(uint256 indexed _operatorId, address indexed _from, uint256 _amount, uint256 _amountOut);
    event EthUnstake(
        uint256 indexed _operatorId, uint256 targetOperatorId, address ender, uint256 _amounts, uint256 amountOut
    );
    event NftUnstake(uint256 indexed _operatorId, uint256 tokenId, uint256 operatorId);
    event NftStake(uint256 indexed _operatorId, address indexed _from, uint256 _count);
    event ValidatorRegistered(uint256 indexed _operatorId, uint256 _tokenId);
    event UserClaimRewards(uint256 _operatorId, uint256[] _tokenIds, uint256 _rewards);
    event Transferred(address _to, uint256 _amount);
    event OperatorReinvestClRewards(uint256 _operatorId, uint256 _rewards);
    event OperatorReinvestElRewards(uint256 _operatorId, uint256 _rewards);
    event RewardsReceive(uint256 _rewards);
    event ArrearsReceiveOfSlash(uint256 _operatorId, uint256 _amount);
    event SlashReceive(uint256 _operatorId, uint256 tokenId, uint256 _slashAmount, uint256 _requirAmounts);
    event LiquidStakingWithdrawalCredentialsSet(
        bytes _oldLiquidStakingWithdrawalCredentials, bytes _liquidStakingWithdrawalCredentials
    );
    event BeaconOracleContractSet(address _oldBeaconOracleContract, address _beaconOracleContractAddress);
    event NodeOperatorRegistryContractSet(
        address _oldNodeOperatorRegistryContract, address _nodeOperatorRegistryContract
    );
    event DaoAddressChanged(address _oldDao, address _dao);
    event DaoVaultAddressChanged(address _oldDaoVaultAddress, address _daoVaultAddress);
    event DepositFeeRateSet(uint256 _oldFeeRate, uint256 _feeRate);
    event OperatorClaimRewards(uint256 _operatorId, uint256 _rewards);
    event DaoClaimRewards(uint256 _operatorId, uint256 _rewards);
    event NftExitBlockNumberSet(uint256[] tokenIds, uint256[] exitBlockNumbers);
    event LargeWithdrawalsRequest(uint256 _operatorId, address sender, uint256 totalNethAmount);
    event VaultManagerContractSet(address vaultManagerContractAddress, address _vaultManagerContract);
    event ConsensusVaultContractSet(address vaultManagerContractAddress, address _consensusVaultContract);
    
    error InvalidParameter();

    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    VaultManager vaultManager;
    NodeOperatorRegistry operatorRegistry;
    WithdrawOracle withdrawOracle;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    ConsensusVault consensusVaultContract;
    address payable consensusVaultContractAddr;
    ILiquidStaking public liquidStakingContract;
    HashConsensusWithTimer consensus;
    INodeOperatorsRegistry  public nodeOperatorsRegistryContract;

    address _dao = DAO;
    address _daoValutAddress = address(2);

    address _rewardAddress = address(3);
    address _rewardAddress2 = address(133);
    address _rewardAddress3 = address(166);
    address _rewardAddress4 = address(255);
    address _rewardAddress5 = address(325);

    address _controllerAddress = address(4);
    address _controllerAddress2 = address(144);
    address _controllerAddress3 = address(246);
    address _controllerAddress4 = address(322);
    address _controllerAddress5 = address(422);

    address _oracleMember1 = address(11);
    address _oracleMember2 = address(12);
    address _oracleMember3 = address(13);
    address _oracleMember4 = address(14);
    address _oracleMember5 = address(15);

    address[] _rewardAddresses = new address[] (1);
    address[] _rewardAddresses2 = new address[] (1);
    address[] _rewardAddresses3 = new address[] (1);
    address[] _rewardAddresses4 = new address[] (1);
    address[] _rewardAddresses5 = new address[] (1);

    uint256[] _ratios = new uint256[] (1);


    function setUp() public {
        _rewardAddresses[0] = address(5);
        _ratios[0] = 100;
        liquidStaking = new LiquidStaking();
        _rewardAddresses2[0] = address(104);
        vm.prank(address(consensusVaultContract) );
        consensusVaultContract = new ConsensusVault();
        consensusVaultContract.initialize(_dao, address(liquidStaking));
        consensusVaultContractAddr = payable(consensusVaultContract);
        console.log(" address(liquidStaking): ", address(liquidStaking) );

        liquidStakingContract = ILiquidStaking(address(liquidStaking));

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();
        vaultFactoryContract = new ELVaultFactory();
        vm.prank(address(vaultFactoryContract) );
        vaultFactoryContract.initialize(address(vaultContract), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress, address(vaultFactoryContract), address(vnft));
        vm.prank(_dao);
        operatorRegistry.setLiquidStaking(address(liquidStaking));
        vm.prank(address(vaultFactoryContract) );
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));
        nodeOperatorsRegistryContract = INodeOperatorsRegistry(address(operatorRegistry));

        depositContract = new DepositContract();

        (consensus, withdrawOracle) = deployWithdrawOracleMock();
        vm.startPrank(_dao);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 3);
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 3);
        withdrawOracle.setLiquidStaking(address(liquidStaking));
        vm.stopPrank();

        liquidStaking.initialize(
            _dao,
            _daoValutAddress,
            hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106",
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(withdrawOracle),
            address(depositContract)
        );

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "one", _controllerAddress, address(4), _rewardAddresses, _ratios
        );

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "two", address(_controllerAddress2), address(5), _rewardAddresses2, _ratios
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        vaultManager = new VaultManager();
        vm.prank(address(vaultManager));
        vaultManager.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawOracle),
            address(consensusVaultContract)
        );
        vm.prank(_dao);
        liquidStaking.setVaultManagerContract(address(vaultManager));

    }

    function testStakeEthFailRequireCases() public {
        vm.expectRevert(0x2c5211c6); //revert InvalidAmount();
        vm.prank(address(2));
        vm.deal(address(2), 12 ether);
        vm.deal(address(3), 12 ether);

        liquidStaking.stakeETH{value: 100 wei}(1);

        vm.expectRevert(0x2c5211c6); //revert InvalidAmount();
        vm.prank(address(2));
        liquidStaking.stakeETH{value: 200 wei}(1);

        vm.expectRevert(0xdc0ca7f3); //revert RequireOperatorTrusted();
        liquidStaking.stakeETH{value: 1 ether}(2);

        vm.expectRevert(0xae4207eb); //revert OperatorNotFound();
        vm.prank(address(2));
        liquidStaking.stakeETH{value: 1 ether}(13);

    }

    
    function testRegisterOperatorFailRequireCases() public {
        vm.prank(address(45));
        vm.deal(address(45), 22 ether);
        vm.expectRevert("Insufficient amount");
        operatorRegistry.registerOperator{value: 0.1 ether}(
            "three", address(_controllerAddress3), address(13), _rewardAddresses3, _ratios
        );
        vm.prank(address(45));
        vm.expectRevert("EMPTY_ADDRESS");
        operatorRegistry.registerOperator{value: 1.1 ether}(
            "four", address(_controllerAddress4), address(14), _rewardAddresses4, _ratios
        );
        vm.expectRevert("Invalid length");
        string memory _longName = "123142141212131223123122112231231312323123142341";
        vm.prank(address(45));
        operatorRegistry.registerOperator{value: 1.1 ether}(
            _longName, address(_controllerAddress5), address(15), _rewardAddresses5, _ratios
        );

        vm.expectRevert("EMPTY_ADDRESS");
        vm.prank(address(45));
        operatorRegistry.registerOperator{value: 1.1 ether}(
            "five", address(_controllerAddress5), address(5), _rewardAddresses5, _ratios
        );
        
        vm.roll(100);
        address[] memory _rewardAddresses6 = new address[] (2);
        uint256[] memory _ratios6 = new uint256[] (2);
        _rewardAddresses6[0] = address(50);
        _rewardAddresses6[1] = address(71);
        _ratios6[0] = 70;
        _ratios6[1] = 20;

        address _controllerAddress6 = address(80);
        address _owner6 = address(81);
        vm.expectRevert("Invalid Ratio");

        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testOperator1", _controllerAddress6, _owner6, _rewardAddresses6, _ratios6
        );
        vm.expectRevert("Invalid length");

        uint256 operatorId2 = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testOperator2", _controllerAddress6, _owner6, _rewardAddresses6, _ratios
        );

    }

    function testConsensusVaultFailCases() public {
        vm.deal(address(consensusVaultContract), 100 ether);
        assertEq(100 ether, address(consensusVaultContract).balance);
        vm.expectRevert("Not allowed to touch funds");
        vm.prank(address(122));
        consensusVaultContract.transfer(50 ether, address(60));
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(111));
        consensusVaultContract.setLiquidStaking(address(61));
        console.log("consensusVaultContract.owner(): ", consensusVaultContract.owner() );
        vm.expectRevert("LiquidStaking address invalid");
        consensusVaultContract.setLiquidStaking(address(0));
    }

    function testELVaultFactoryFailCases() public {
        vm.prank(address(vaultFactoryContract));
        vaultFactoryContract.setNodeOperatorRegistry(address(70));
        assertEq(vaultFactoryContract.nodeOperatorRegistryAddress(), address(70));

        vm.prank(address(vaultFactoryContract) );
        vm.expectRevert("nodeOperator registry address invalid");
        vaultFactoryContract.setNodeOperatorRegistry(address(0));

        vm.prank(address(vaultFactoryContract) );
        vm.expectRevert("Dao address invalid");
        vaultFactoryContract.setDaoAddress(address(0));

        uint256[] memory operatorIds = new uint256[](1);
        operatorIds[0] = 1 ;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 ;
        vm.expectRevert(0x613970e0);  //revert InvalidParameter()
        vm.prank(address(vaultManager) );
        liquidStakingContract.reinvestClRewards(operatorIds, amounts); //
        vm.expectRevert(        ); //revert PermissionDenied();
        vm.prank(address(111) );
        liquidStakingContract.reinvestClRewards(operatorIds, amounts); 


        uint256[] memory _exitTokenIds = new uint256[] (2);
        _exitTokenIds[0] = 0;
        _exitTokenIds[1] = 1;
        uint256[] memory _amounts = new uint256[] (1);
        _amounts[0] = 0.2 ether;

        vm.prank(address(vaultManager));
        vm.expectRevert(0x613970e0);
        liquidStaking.reinvestElRewards(operatorIds, amounts);

    }

    function testRegisterValidatorFailCases() public {

        bytes[] memory pubkeys1 = new bytes[](2);
        bytes[] memory signatures1 = new bytes[](1);
        bytes32[] memory depositDataRoots1 = new bytes32[](1);

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000d9e2dc13b0d2f6f73cd21c32fbf7de143c558e29")
        );
         bytes memory pubkey1 =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
        bytes memory sign1 = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root1 = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");

        pubkeys1[0] = pubkey1;
        signatures1[0] = sign1;
        depositDataRoots1[0] = root1;
        vm.prank(address(_controllerAddress));
        vm.expectRevert(0x613970e0);
        liquidStaking.registerValidator(pubkeys1, signatures1, depositDataRoots1);

        
        // vm.prank(_dao);
        // operatorRegistry.setBlacklistOperator(operatorId);

    }

    function testInitializeV2() public {
        uint256[] memory _operatorIds = new uint256[] (1);
        _operatorIds[0] = 1;
        address[] memory _users  = new address[] (1);
        _users[0] = address(1);
        uint256[] memory _nethAmounts  = new uint256[] (1);
        _nethAmounts[0] = 1;
        address _consensusVaultContractAddress = address(5001);
        address _vaultManagerContractAddress= address(5002);
        address _withdrawalRequestContractAddress =address(5003);
        address _operatorSlashContractAddress =address(5004);
        vm.prank(_dao);
        liquidStaking.initializeV2(_operatorIds, _users, _nethAmounts, _consensusVaultContractAddress, 
        _vaultManagerContractAddress, _withdrawalRequestContractAddress, _operatorSlashContractAddress ) ;
        // assertEq(2000000000000 , liquidStaking.slashAmountPerBlockPerValidator() );
        assertEq( 32 ether , liquidStaking.operatorCanLoanAmounts() );
    }


    function testMscFunctions() public{

        vm.deal(address(301), 100 ether);
        vm.prank(address(301));
        liquidStakingContract.receiveRewards{value: 1 ether}(1 ether) ;
        vm.deal(_dao, 2000 ether);
       
        vm.expectRevert(0x613970e0);
        vm.prank(_dao);
        liquidStaking.setOperatorCanLoanAmounts( 1001 ether);
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistryContractSet( address(operatorRegistry), address(4001) );
        vm.prank(_dao);
        liquidStaking.setNodeOperatorRegistryContract(address(4001));
       
        console.log("(address(operatorRegistry): ", address(operatorRegistry));
        bytes4 _bytes= liquidStaking.onERC721Received(address(1111), address(1112), 1,  bytes(hex"0100000000000000000000006ae2f56c057e31a18224dbc6ae32b0a5fbedfcb0"));
       
        vm.expectEmit(true, true, false, true);
        emit BeaconOracleContractSet( address(withdrawOracle), address(4002) );        
        vm.prank(_dao);
        liquidStaking.setBeaconOracleContract(address(4002));


    }

    function testClaimRewardsOfDao() public{
        vm.roll(100);

        address _controllerAddress = address(2111);
        address _owner = address(2112);
        address _to = address(2113);
        address[] memory _testRewardAddresses = new address[] (2);
        uint256[] memory _ratios = new uint256[] (2);
        _testRewardAddresses[0] = address(2114);
        _testRewardAddresses[1] = address(2115);
        _ratios[0] = 50;
        _ratios[1] = 50;
        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test3", _controllerAddress, _owner, _testRewardAddresses, _ratios
        );


        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId);

        vm.deal(address(73), 100 ether);
        vm.prank(address(73));
        liquidStaking.stakeETH{value: 64 ether}(operatorId);
        assertEq(0, vnft.balanceOf(address(73)));
        assertEq(64 ether, neth.balanceOf(address(73)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(64 ether, liquidStaking.operatorPoolBalances(operatorId));

        // registerValidator 1
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106")
        );
        bytes memory pubkey =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

        address vaultContractAddress;
        (,,,, vaultContractAddress) = operatorRegistry.getNodeOperator(operatorId, false);

        assertEq(address(vaultContractAddress).balance, 0);
        payable(vaultContractAddress).transfer(10 ether);
        assertEq(address(vaultContractAddress).balance, 10 ether);

        assertEq(32 ether, liquidStaking.operatorPoolBalances(operatorId));
    

        uint256[] memory operatorIds = new uint256[] (1);
        operatorIds[0] = operatorId;
        vaultManager.settleAndReinvestElReward(operatorIds);
        // assertEq(9 ether, liquidStaking.operatorPoolBalances(operatorId)); // reinvest
        console.log("liquidStaking.operatorPoolBalances(operatorId): ", liquidStaking.operatorPoolBalances(operatorId));
        // assertEq(vaultManager.daoRewardsMap(operatorId), 0.3 ether);
        // assertEq(vaultManager.operatorRewardsMap(operatorId), 0.7 ether);

        // assertEq(address(_daoValutAddress).balance, 0.2 ether); // registerOperator * 2 = 0.1 * 2

        // vaultManager.claimRewardsOfOperator(operatorId);
        // vaultManager.claimRewardsOfDao(operatorIds);

        // assertEq(address(vaultContractAddress).balance, 0 ether);

        // assertEq(address(_daoValutAddress).balance, 0.5 ether); // 0.2 + 0.3
        // assertEq(0.49 ether, _rewardAddresses3[0].balance); // 0.7 * 0.7
        // assertEq(0.14 ether, _rewardAddresses3[1].balance); // 0.7 * 0.2
        // assertEq(0.07 ether, _rewardAddresses3[2].balance); // 0.7 * 0.1

        // assertEq(64 ether, neth.totalSupply());
        // assertEq(73 ether, liquidStaking.getTotalEthValue()); // 64 ether + 9 ether
    }


}
