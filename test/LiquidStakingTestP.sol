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
import "src/vault/NodeDaoTreasury.sol";
import "test/helpers/oracles/MultiHashConsensusWithTimer.sol";
import "test/helpers/oracles/MockMultiOracleProvider.sol";
import "test/helpers/oracles/WithdrawOracleWithTimer.sol";
import "test/helpers/CommonConstantProvider.sol";
import "src/interfaces/ILiquidStaking.sol";
import {WithdrawInfo, ExitValidatorInfo} from "src/library/ConsensusStruct.sol";
import "src/OperatorSlash.sol";
import "src/WithdrawalRequest.sol";
import "src/largeStaking/LargeStaking.sol";
import "src/largeStaking/ELReward.sol";
import "src/largeStaking/ELRewardFactory.sol";
import {CLStakingExitInfo, CLStakingSlashInfo} from "src/library/ConsensusStruct.sol";

// forge test --match-path  test/LiquidStakingTestP.sol
contract LiquidStakingTestP is Test, MockMultiOracleProvider {
    error PermissionDenied();
    error RequireBlacklistOperator();
    error AssignMustSameOperator();
    error InvalidParameter();
    error RequireOperatorTrusted();
    error InvalidAmount();
    error InsufficientMargin();
    error InvalidDaoVaultAddr();
    error UnstakeEthNoQuota();
    error OperatorLoanFailed();
    error InvalidWithdrawalCredentials();
    error InsufficientFunds();
    error OperatorHasArrears();
    error TotalEthIsZero();
    error InvalidCommission();
    
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
    event FastUnstake(uint256 _stakingId, uint256 _unstakeAmount);
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
    event LargeStake( uint256 _operatorId, uint256 _curStakingId, uint256 _amount, address _owner, address _withdrawCredentials, bool _isELRewardSharing );    
    event MigretaStake( uint256 _operatorId, uint256 _curStakingId, uint256 _amount, address _owner, address _withdrawCredentials, bool _isELRewardSharing );    event AppendStake(uint256 _stakingId, uint256 _amount);

    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    VaultManager vaultManager;
    NodeOperatorRegistry operatorRegistry;
    WithdrawOracle withdrawOracle;
    MockMultiReportProcessor reportProcessor1;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    ConsensusVault consensusVaultContract;
    address payable consensusVaultContractAddr;
    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;
    NodeDaoTreasury nodeDaoTreasury;
    MultiHashConsensusWithTimer consensus;
    LargeStaking largeStaking;
    ELReward elReward;
    ELRewardFactory elRewardFactor;

    address _dao = DAO;
    address _daoValutAddress;
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
    address _controllerAddress2 = address(14);
    address _controllerAddress3 = address(24);

    address _owner = address(5);
    address _owner2 = address(6);
    address _owner3 = address(6);
    address _oracleMember1 = address(11);
    address _oracleMember2 = address(12);
    address _oracleMember3 = address(13);
    address _oracleMember4 = address(14);
    address _oracleMember5 = address(15);
    address[] _rewardAddresses = new address[] (1);
    address[] _rewardAddresses2 = new address[] (1);
    address[] _rewardAddresses3 = new address[] (1);

    uint256[] _ratios = new uint256[] (1);

    function setUp() public {
        _rewardAddresses[0] = address(5);
        _rewardAddresses2[0] = address(6);
        _rewardAddresses3[0] = address(7);
        _ratios[0] = 100;
        liquidStaking = new LiquidStaking();

        consensusVaultContract = new ConsensusVault();
        consensusVaultContract.initialize(_dao, address(liquidStaking));
        consensusVaultContractAddr = payable(consensusVaultContract);

        nodeDaoTreasury = new NodeDaoTreasury(_dao);
        _daoValutAddress = address(nodeDaoTreasury);

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();
        vaultFactoryContract = new ELVaultFactory();
        vaultFactoryContract.initialize(address(vaultContract), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress, address(vaultFactoryContract), address(vnft));
        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(liquidStaking), address(0), address(0), address(0), 0, 0, 0
        );
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

        depositContract = new DepositContract();

        consensus = deployMultiHashConsensusMock();
        withdrawOracle = deployWithdrawOracleMock(address(consensus));
        reportProcessor1 = new MockMultiReportProcessor(CONSENSUS_VERSION);

        vm.startPrank(_dao);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        consensus.addReportProcessor(address(withdrawOracle));
        consensus.addReportProcessor(address(reportProcessor1));

        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 3);
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 3);
        withdrawOracle.setLiquidStaking(address(liquidStaking));
        withdrawOracle.updateContractVersion(CONSENSUS_VERSION);

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
            "one", _controllerAddress, _owner, _rewardAddresses, _ratios
        );



        assertEq(0.1 ether, _daoValutAddress.balance);
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "two", _controllerAddress2, _owner2, _rewardAddresses2, _ratios
        );
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(2);

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "three", _controllerAddress3, _owner3, _rewardAddresses3, _ratios
        );
        vaultManager = new VaultManager();

        uint256[] memory _operatorIds = new uint256[](0);
        address[] memory _users = new address[](0);
        uint256[] memory _nethAmounts = new uint256[](0);

        withdrawalRequest = new WithdrawalRequest();
        withdrawalRequest.initialize(
            _dao, address(liquidStaking), address(vnft), address(neth), address(operatorRegistry), address(vaultManager)
        );

        operatorSlash = new OperatorSlash();
        operatorSlash.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawalRequest),
            address(vaultManager),
            7200
        );

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(operatorSlash), address(0), address(0), 0, 0, 0
        );

        vm.prank(_dao);
        liquidStaking.initializeV2(
            _operatorIds,
            _users,
            _nethAmounts,
            address(consensusVaultContract),
            address(vaultManager),
            address(withdrawalRequest),
            address(operatorSlash),
            address(withdrawOracle)
        );

        vaultManager.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawOracle),
            address(operatorSlash)
        );
        vm.prank(_dao);
        vaultManager.setDaoElCommissionRate(300);

        uint256[] memory _resetVaultOperatorIds = new uint256[] (1);
        _resetVaultOperatorIds[0] = 1;

        assertEq(operatorRegistry.defaultOperatorCommission(), 0);
        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("========operatorRegistry.initializeV2==========", operatorVaultAddr);
        vm.prank(_dao);
        operatorRegistry.initializeV2(address(vaultFactoryContract), address(operatorSlash), _resetVaultOperatorIds);
        operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("========operatorRegistry.initializeV2==========", operatorVaultAddr);
        assertEq(operatorRegistry.defaultOperatorCommission(), 2000);

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(0), address(0), 1000, 0, 0
        );

        assertEq(operatorRegistry.defaultOperatorCommission(), 1000);

        elReward = new ELReward();
        elRewardFactor = new ELRewardFactory();
        elRewardFactor.initialize(address(elReward), _dao);
        largeStaking = new LargeStaking();
        largeStaking.initialize(
            _dao,
            _daoValutAddress,
            address(operatorRegistry),
            address(operatorSlash),
            address(withdrawOracle),
            address(elRewardFactor),
            address(depositContract)
        );
        vm.prank(_dao);
        operatorRegistry.initializeV3(address(largeStaking));

        vm.prank(_dao);
        largeStaking.setLargeStakingSetting(
            address(0), address(0), 1500, 0, address(0), address(0), address(0), address(0)
        );
        vm.prank(_dao);
        operatorSlash.initializeV2(address(largeStaking));
    }


    // function _stakePoolValidator() internal {
    //     vm.deal(address(75), 64 ether);
    //     vm.prank(address(75));
    //     liquidStaking.stakeETH{value: 64 ether}(1);
    //     assertEq(0, vnft.balanceOf(address(75)));
    //     assertEq(64 ether, neth.balanceOf(address(75)));
    //     assertEq(0, vnft.balanceOf(address(liquidStaking)));
    //     assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

    //     assertEq(64 ether, liquidStaking.operatorPoolBalances(1));

    //     bytes[] memory pubkeys = new bytes[](1);
    //     bytes[] memory signatures = new bytes[](1);
    //     bytes32[] memory depositDataRoots = new bytes32[](1);

    //     liquidStaking.setLiquidStakingWithdrawalCredentials(
    //         bytes(hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106")
    //     );
    //     bytes memory pubkey =
    //         bytes(hex"a369806d61ade95f1f0395473e5c5bd633bde38d6abba3a9b1c2fe2049a27a4008cfd9643a4b8162853e37f41c957c6b");
    //     bytes memory sign = bytes(
    //         hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
    //     );
    //     bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
    //     pubkeys[0] = pubkey;
    //     signatures[0] = sign;
    //     depositDataRoots[0] = root;

    //     assertEq(vnft.validatorExists(pubkey), false);
    //     vm.prank(address(_controllerAddress));
    //     liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

    //     liquidStaking.setLiquidStakingWithdrawalCredentials(
    //         bytes(hex"010000000000000000000000d9e2dc13b0d2f6f73cd21c32fbf7de143c558e29")
    //     );
    //     pubkey =
    //         bytes(hex"804424fd3989527628d71618cc0964f1934a778af35fae602b775f92a326863677f705f9b4fd264dbc66b328d7b09721");
    //     sign = bytes(
    //         hex"b0e13147956deb0b188e79de8181d0f9f216a43cf8fe0435c5c919da0182400e440ff6ba11d1c2ec12bec824200d9d07130d53260e8f03d7292af14e909731435ffe5beb4e97f7e97e55cd555e99e23de6dbb5618a40bd26b7537b9cd4104370"
    //     );
    //     root = bytes32(hex"f497234b67c6258b9cd46627adb7a88a26a5b48cbe90ee3bdb24bf9c559a0595");
    //     pubkeys[0] = pubkey;
    //     signatures[0] = sign;
    //     depositDataRoots[0] = root;

    //     assertEq(vnft.validatorExists(pubkey), false);
    //     vm.prank(address(_controllerAddress));
    //     liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
    // }


    // // LargeStaking
    // function testFailLargeStaking() public {
    //     vm.deal(address(1000), 3200 ether);
    //     vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
    //     vm.prank(address(1000));
    //     largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
    // }


    // function testLargeStaking() public {

    //     vm.expectRevert(abi.encodeWithSignature("PermissionDenied()"));
    //     vm.prank(address(1221));
    //     largeStaking.startupSharedRewardPool(1);

    //     vm.prank(_owner);
    //     largeStaking.startupSharedRewardPool(1);

    //     vm.prank(_owner2);
    //     largeStaking.startupSharedRewardPool(2);

    //     // shared reward 0 , set _isELRewardSharing as true 
    //     // vm.deal(address(1000), 320 ether);
    //     vm.deal(address(1000), 320 ether);
    //     vm.deal(address(555) , 1);
    //     vm.prank(address(1000));
    //     largeStaking.largeStake{value: 320 ether}(1, address(1000), address(555), true);
    //     (uint256 operatorId, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(1);
    //     // return after reporting daoReward, operatorReward, as 0 
    //     // console.log("1. largeStaking.reward(1):  ", largeStaking.reward(1));
    //     // console.log("1. rewards:  ", rewards );
    //     assertEq(largeStaking.totalShares(1), 320 ether); 


    //     vm.deal(rewardPoolAddr, 10 ether);  
    //     //  shared reward 2, set _isELRewardSharing as true 
    //     vm.deal(address(1002), 320 ether);
    //     vm.deal(address(555), 1);
    //     vm.prank(address(1002));
    //     largeStaking.largeStake{value: 320 ether}(1, address(1002), address(555), true);
    //     (uint256 operatorId2, address rewardPoolAddr2, uint256 rewards2) = largeStaking.getRewardPoolInfo(1);
    //     assertEq(rewardPoolAddr, rewardPoolAddr2);
    //     // console.log("2. rewardPoolAddr:  ", rewardPoolAddr );
    //     // console.log("2. rewards2:  ", rewards2 );
    //     // console.log("2. largeStaking.reward(1):  ", largeStaking.reward(1));


    //     // uint256 _valuePerShare = 7.5 ether * 1e18 / 640 ether * 2 ;
    //     // assertEq(largeStaking.totalShares(1), 640 ether);
    //     // assertEq(largeStaking.valuePerShare(1), _valuePerShare );
    //     // assertEq(largeStaking.reward(1), 7.5 ether);
    //     assertEq(largeStaking.operatorSharedRewards(1), 1 ether);
    //     largeStaking.settleElSharedReward(1) ;
    //     console.log("largeStaking.operatorSharedRewards(1): ", largeStaking.operatorSharedRewards(1));
    //     // assertEq(largeStaking.daoSharedRewards(1), 1.5  ether);
    //     // assertEq(largeStaking.reward(2), 0 ether);


    //     // // claim reward
    //     vm.prank(address(1000));
    //     largeStaking.claimRewardsOfUser(1, address(1000), 5.5 ether);
    //     assertEq(largeStaking.reward(1), 2 ether);
    //     assertEq(address(1000).balance, 5.5 ether);

    //     vm.deal(address(1003), 320 ether);
    //     vm.deal(address(666), 1);

    //     vm.prank(address(1003));
    //     largeStaking.largeStake{value: 320 ether}(2, address(1003), address(666), true);
    //     (uint256 operatorId3, address rewardPoolAddr3, uint256 rewards3) = largeStaking.getRewardPoolInfo(3);
    //     // assertEq(rewardPoolAddr, rewardPoolAddr3);
    //     // console.log("3. rewardPoolAddr3:  ", rewardPoolAddr3 );
    //     // console.log("3. rewards3:  ", rewards3 );
    //     // console.log("3. largeStaking.reward(2):  ", largeStaking.reward(3));


    //     vm.deal(rewardPoolAddr3, 8 ether); // simulate of rewards send to rewardPool. 

    //     vm.deal(address(1004), 320 ether);
    //     vm.prank(address(1004));
    //     largeStaking.largeStake{value: 320 ether}(2, address(1004), address(666), true);
    //     (uint256 operatorId4, address rewardPoolAddr4, uint256 rewards4) = largeStaking.getRewardPoolInfo(4);
    //     assertEq(rewardPoolAddr3, rewardPoolAddr4);
    //     console.log("4. rewards4:  ", rewards4 );
    //     assertEq(largeStaking.totalShares(2), 640 ether);
    //     // 8 ether rewards shared between operator, dao, pool
    //     // console.log("4. operatorSharedRewards(2):  ", largeStaking.operatorSharedRewards(2) );
    //     // console.log("4. daoSharedRewards(2):  ", largeStaking.daoSharedRewards(2) );
    //     // console.log("4. reward(3):  ", largeStaking.reward(3) );

    //     assertEq(largeStaking.daoSharedRewards(2), 1.2 ether);
    //     assertEq(largeStaking.reward(3), 6 ether);
    //     largeStaking.settleElSharedReward(2);
    //     assertEq(largeStaking.operatorSharedRewards(2), 0.8 ether);

    //     // private 1 , set _isELRewardSharing as false 
    //     vm.deal(address(1001), 960 ether);
    //     vm.deal(address(555), 1);
    //     vm.prank(address(1001));
    //     largeStaking.largeStake{value: 960 ether}(1, address(1001), address(555), false);
    //     (uint256 operatorId5, address rewardPoolAddr5, uint256 rewards5) = largeStaking.getRewardPoolInfo(3);
    //     // console.log("5. rewards5:  ", rewards5 );
    //     // console.log("5. largeStaking.reward(4):  ", largeStaking.reward(4));
    //     // assertEq(largeStaking.totalShares(1), 640 ether);
    // }

    function testClaimRewardsOfDao() public {

        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);
        vm.prank(_owner2);
        largeStaking.startupSharedRewardPool(2);

        vm.deal(address(1000), 320 ether);
        vm.deal(address(555) , 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), address(555), true);
        (uint256 operatorId, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(1);

        uint256[] memory _privatePoolStakingIds = new uint256[] (1);
        _privatePoolStakingIds[0] = 1; 
        largeStaking.claimRewardsOfOperator(_privatePoolStakingIds, true , 1);

        vm.deal(rewardPoolAddr, 10 ether);  
        //  shared reward 2, set _isELRewardSharing as true 
        vm.deal(address(1002), 320 ether);
        vm.deal(address(555), 1);
        vm.prank(address(1002));
        largeStaking.largeStake{value: 320 ether}(1, address(1002), address(555), true);


        largeStaking.settleElSharedReward(1) ;
        assertEq( largeStaking.operatorSharedRewards(1) , 1 ether);
        assertEq( largeStaking.unclaimedSharedRewards(1) , 10 ether);

        // // claim reward
        vm.prank(address(1000));
        largeStaking.claimRewardsOfUser(1, address(1000), 5.5 ether);

        console.log("B unclaimedSharedRewards: ",  largeStaking.unclaimedSharedRewards(1) );
        assertEq( largeStaking.unclaimedSharedRewards(1) , 4.5 ether);

        assertEq( largeStaking.daoSharedRewards(1) , 1.5 ether);
        uint256[] memory privatePoolStakingIds = new uint256[] (1);
        privatePoolStakingIds[0] = 1; 
        largeStaking.claimRewardsOfDao(privatePoolStakingIds, privatePoolStakingIds);
        assertEq( largeStaking.daoSharedRewards(1) , 0  );
        vm.deal(address(1003), 320 ether);
        vm.deal(address(666), 1);

        vm.prank(address(1003));
        largeStaking.largeStake{value: 320 ether}(2, address(1003), address(666), true);
        (uint256 operatorId3, address rewardPoolAddr3, uint256 rewards3) = largeStaking.getRewardPoolInfo(3);
        
        vm.deal(rewardPoolAddr3, 8 ether); // simulate of rewards send to rewardPool. 

        vm.deal(address(1004), 320 ether);
        vm.prank(address(1004));
        largeStaking.largeStake{value: 320 ether}(2, address(1004), address(666), true);
        (uint256 operatorId4, address rewardPoolAddr4, uint256 rewards4) = largeStaking.getRewardPoolInfo(4);

        // private 1 , set _isELRewardSharing as false 
        vm.deal(address(1001), 960 ether);
        vm.deal(address(555), 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), address(555), false);

    }


     function testLargeStakeFail() public {
        vm.deal(address(111), 1000 ether);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(address(111));
        largeStaking.largeStake{value: 319 ether}(1, address(1111), address(1112), false );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        largeStaking.largeStake{value: 2 ether}(2, address(1111), address(1112), false );
        assertEq(largeStaking.getOperatorValidatorCounts(2), 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        largeStaking.largeStake{value: 2 ether}(2, address(1111), address(1112), true );
        assertEq(largeStaking.getOperatorValidatorCounts(2), 0);

        vm.expectRevert(abi.encodeWithSignature("OperatorNotFound()"));
        largeStaking.largeStake{value: 320 ether}(999, address(1111), address(1112), false );
        assertEq(largeStaking.getOperatorValidatorCounts(999), 0);

        vm.expectRevert(abi.encodeWithSignature("RequireOperatorTrusted()"));
        largeStaking.largeStake{value: 320 ether}(3, address(1111), address(1112), false );
        assertEq(largeStaking.getOperatorValidatorCounts(2), 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidWithdrawalCredentials()"));
        largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidWithdrawalCredentials()"));
        largeStaking.largeStake{value: 320 ether}(1, address(0), address(1112), false );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 0);
        
        vm.deal(address(1112), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("SharedRewardPoolNotOpened()"));
        largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), true );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 0);
        
        // successful test case
        vm.expectEmit(true, true, false, true);
        emit LargeStake(1, 1 , 320 ether, address(1111), address(1112), false);
        vm.prank(address(111));
        largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );

        // getOperatorValidatorCounts
        assertEq(largeStaking.getOperatorValidatorCounts(1), 10);
        
        ( bool isELRewardSharing, uint256 stakingId, uint256 operatorId, uint256 stakingAmount,
         uint256 alreadyStakingAmount, uint256 unstakeRequestAmount, uint256 unstakeAmount,
          address owner, bytes32 withdrawCredentials )
         = largeStaking.largeStakings(1) ; 

        // Access the individual components of the stakingInfo
        assertEq(isELRewardSharing , false);
        assertEq(operatorId , 1);
        assertEq(stakingId , 1);
        assertEq(stakingAmount , 320 ether);
        assertEq(alreadyStakingAmount , 0);
        assertEq(unstakeRequestAmount , 0);
        assertEq(unstakeAmount , 0);
        assertEq(owner , address(1111) );
        console.logBytes32(  withdrawCredentials );

    } 


    function testAppendLargeStake() public {

        vm.deal(address(1111), 1000 ether);
        vm.deal(address(2222), 1000 ether);
        vm.deal(address(1112), 1 ether);

        vm.prank(address(1111));
        largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 10);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(address(2222));
        largeStaking.appendLargeStake{value: 311 ether}(0, address(2222), address(2223) );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 10);  

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(address(1111));
        largeStaking.appendLargeStake{value: 2 ether}(1, address(1111), address(2222) );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 10);  

        largeStaking.appendLargeStake{value: 320 ether}(1, address(1111), address(1112)  );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 20);

        largeStaking.appendLargeStake{value: 320 ether}(1, address(1111), address(1112)  );
        assertEq(largeStaking.getOperatorValidatorCounts(1), 30);

    }

    function testLargeUnstake() public {
        vm.deal(address(1111), 320 ether);
        vm.prank(address(1111));
        vm.deal(address(1112), 1 ether);
            largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );
            assertEq(largeStaking.getOperatorValidatorCounts(1), 10);

            vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
            vm.prank(address(1111));
            largeStaking.largeUnstake(0, 16 ether );
            assertEq( address(1111).balance  , 0);

            // // successful test case
            vm.expectEmit(true, true, false, true);
            emit FastUnstake(1, 64 ether);
            vm.prank(address(1111));
            largeStaking.largeUnstake(1, 64 ether );
            assertEq(largeStaking.getOperatorValidatorCounts(1), 8);

            assertEq( address(1111).balance  ,  64 ether  );
            assertEq( address(1112).balance  ,  1 ether  );

            vm.expectEmit(true, true, false, true);
            emit FastUnstake(1, 128 ether);
            vm.prank(address(1111));
            largeStaking.largeUnstake(1, 128 ether );
            assertEq( address(1111).balance  ,  192 ether  );

    }


    function testMigrateStakeFailCases() public {
        // RequireOperatorTrusted()
        bytes[] memory _pubkeys = new bytes[] (1);
        _pubkeys[0] = bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920523a3");
        vm.expectRevert(abi.encodeWithSignature("RequireOperatorTrusted()"));
        vm.prank(address(888));
        largeStaking.migrateStake(address(1111), address(1111), false, _pubkeys );


        vm.expectRevert(0xdc0ca7f3);
        largeStaking.migrateStake(address(5555), address(5556), false, _pubkeys );

    }

    function testMigrateStake() public {

        vm.deal(address(3332) , 1);
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);
        bytes[] memory pubkeys2 = new bytes[] (2);
        pubkeys2[0] =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        pubkeys2[1] =
            bytes(hex"a646616d3f394e9addff2d5e6744cf7923347ce5fc8358148875647fe227abe154331a3b3a6312f6f2ef39dd746c7ca8");

        vm.prank(_controllerAddress);
        vm.expectEmit(true, true, false, true);
        emit MigretaStake(1, 1, 64 ether, address(3331) , address(3332), true) ;
        largeStaking.migrateStake(
            address(3331) , address(3332), true, pubkeys2
        );

        vm.prank(address(3331) );
        largeStaking.largeUnstake(1, 32 ether);

        pubkeys2[0] =
            bytes(hex"8b428f69290c6689d594b90c9256e48cc89ae852c233825146013e65c1cc0555248b89b5a0dfd3e61613bc9b9ed306b8");
        pubkeys2[1] =
            bytes(hex"972213419397cfd4c01c7325738d6ae7b3ffbd49a576623f4fd50215db51e56b5e1f31983dcc10eafdf4b5bd598db0ff");
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter()"));
        largeStaking.appendMigrateStake(
            1, address(444), address(444), pubkeys2
        );
    }

    function testRegisterValidatorFailCases() public {

    }

    function testLargeStakingRegisterValidator() public {
        vm.deal(address(1001), 960 ether);
        vm.deal(address(666) , 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), address(666) , false);
        (uint256 operatorId1, address rewardPoolAddr1, uint256 rewards1) = largeStaking.getRewardPoolInfo(1);

        uint256[] memory operatorIds = new uint256[] (1);
        operatorIds[0] = 1; 
        vm.expectRevert(abi.encodeWithSignature("InvalidCommission()"));
        vm.prank(_dao);
        operatorRegistry.setOperatorCommissionRate(1, 6000);

        assertEq(operatorRegistry.getOperatorCommissionRate(operatorIds)[0], 1000);
        vm.prank(_dao);
        operatorRegistry.setOperatorCommissionRate(1, 350);
        assertEq(operatorRegistry.getOperatorCommissionRate(operatorIds)[0], 350);
        vm.deal(rewardPoolAddr1, 10 ether);
        assertEq(largeStaking.reward(1), 8.15 ether);

        largeStaking.settleElPrivateReward(1);
        assertEq(largeStaking.reward(1), 8.15 ether);
        assertEq(largeStaking.daoPrivateRewards(1), 1.5 ether);
        assertEq(largeStaking.operatorPrivateRewards(1), 0.35 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 10 ether);

        assertEq(largeStaking.totalShares(1), 0 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 30);
        vm.prank(address(1001));
        largeStaking.largeUnstake(1, 320 ether);
        assertEq(address(1001).balance, 320 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 20);

        vm.prank(address(1001));
        
        largeStaking.claimRewardsOfUser(1, address(1001), 8 ether);
        // assertEq(largeStaking.reward(1), 0.15 ether);

        assertEq(address(1001).balance, 328 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 2 ether);

        // shared reward
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);

        vm.deal(address(1000), 320 ether);
        vm.deal(address(666), 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), address(666), true);
        (uint256 operatorId2, address rewardPoolAddr2, uint256 rewards2) = largeStaking.getRewardPoolInfo(2);
        assertEq(largeStaking.totalShares(1), 320 ether);
        assertEq(largeStaking.totalShares(1), 320 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 30);

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
        signatures[0] = sign;
        depositDataRoots[0] = root;

        vm.prank(_controllerAddress);
        largeStaking.registerValidator(1, pubkeys, signatures, depositDataRoots);

        console.log("getValidatorsOfStakingId 1 : ", largeStaking.getValidatorsOfStakingId(1).length);

        pubkeys[0] =
            bytes(hex"93943bd530b79623af943a2af636f06c327203d82784fafda621439438c418bd8d26c82061bbc956fc7f0f8ddb138173");
        vm.prank(_controllerAddress);
        largeStaking.registerValidator(2, pubkeys, signatures, depositDataRoots);
        assertEq(1, largeStaking.getValidatorsOfStakingId(1).length);
        assertEq(1, largeStaking.getValidatorsOfStakingId(2).length);
    }


}
