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
import "test/helpers/oracles/HashConsensusWithTimer.sol";
import "test/helpers/oracles/MockOracleProvider.sol";
import "test/helpers/oracles/WithdrawOracleWithTimer.sol";
import "test/helpers/CommonConstantProvider.sol";
import "src/interfaces/ILiquidStaking.sol";
import {WithdrawInfo, ExitValidatorInfo} from "src/library/ConsensusStruct.sol";
import "src/OperatorSlash.sol";
import "src/WithdrawalRequest.sol";
import "src/largeStaking/largeStaking.sol";
import "src/largeStaking/ElRewardFactory.sol";

contract LargeStakingTest is Test, MockOracleProvider {
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

    error InvalidAddr();
    error InvalidRewardAddr();
    error InvalidRewardRatio();
    error InvalidReport();

    event BlacklistOperatorAssigned(uint256 indexed _blacklistOperatorId, uint256 _operatorId, uint256 _totalAmount);
    event QuitOperatorAssigned(uint256 indexed _quitOperatorId, uint256 _operatorId, uint256 _totalAmount);
    event EthStake(uint256 indexed _operatorId, address indexed _from, uint256 _amount, uint256 _amountOut);
    event EthUnstake(
        uint256 indexed _operatorId, uint256 targetOperatorId, address ender, uint256 _amounts, uint256 amountOut
    );
    event NftUnstake(uint256 indexed _operatorId, uint256 tokenId, uint256 operatorId);
    event NftStake(uint256 indexed _operatorId, address indexed _from, uint256 _count);
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
    event DaoVaultAddressChanged(address _oldDaoVaultAddress, address _daoVaultAddress);
    event DepositFeeRateSet(uint256 _oldFeeRate, uint256 _feeRate);
    event OperatorClaimRewards(uint256 _operatorId, uint256 _rewards);
    event DaoClaimRewards(uint256 _operatorId, uint256 _rewards);
    event NftExitBlockNumberSet(uint256[] tokenIds, uint256[] exitBlockNumbers);
    event LargeWithdrawalsRequest(uint256 _operatorId, address sender, uint256 total_nethAmount);
    event VaultManagerContractSet(address vaultManagerContractAddress, address _vaultManagerContract);
    event ConsensusVaultContractSet(address vaultManagerContractAddress, address _consensusVaultContract);

    event LargeStake( uint256 _operatorId, uint256 _curStakingId, uint256 _amount, address _owner, address _withdrawCredentials, bool _isELRewardSharing );    
    event MigretaStake( uint256 _operatorId, uint256 _curStakingId, uint256 _amount, address _owner, address _withdrawCredentials, bool _isELRewardSharing );    event AppendStake(uint256 _stakingId, uint256 _amount);
    event ValidatorRegistered(uint256 _operatorId, uint256 _stakeingId, bytes _pubKey);
    event FastUnstake(uint256 _stakingId, uint256 _unstakeAmount);
    event LargeUnstake(uint256 _stakingId, uint256 _amount);
    event ELShareingRewardSettle(uint256 _operatorId, uint256 _daoReward, uint256 _operatorReward, uint256 _poolReward);
    event ElPrivateRewardSettle(
        uint256 _stakingId, uint256 _operatorId, uint256 _daoReward, uint256 _operatorReward, uint256 _poolReward
    );
    event UserRewardClaimed(uint256 _stakingId, address _beneficiary, uint256 _rewards);
    event OperatorRewardClaimed(uint256 _operatorId, address _rewardAddresses, uint256 _rewardAmounts);
    event OperatorPrivateRewardClaimed(uint256 _stakingId, uint256 _operatorId, uint256 _operatorRewards);
    event OperatorSharingRewardClaimed(uint256 _operatorId, uint256 _operatorRewards);
    event DaoPrivateRewardClaimed(uint256 _stakingId, address _daoVaultAddress, uint256 _daoRewards);
    event DaoSharingRewardClaimed(uint256 _operatorId, address daoVaultAddress, uint256 _daoRewards);
    event LargeStakingSlash(uint256[] _stakingIds, uint256[] _operatorIds, uint256[] _amounts);
    event ValidatorExitReport(uint256 _operatorId, uint256 _notReportedUnstakeAmount);
    event DaoAddressChanged(address _oldDao, address _dao);
    event DaoELCommissionRateChanged(uint256 _oldDaoElCommissionRate, uint256 _daoElCommissionRate);
    event NodeOperatorsRegistryChanged(address _oldNodeOperatorRegistryContract, address _nodeOperatorRegistryAddress);
    event ConsensusOracleChanged(address _oldConsensusOracleContractAddr, address _consensusOracleContractAddr);
    event ELRewardFactoryChanged(address _oldElRewardFactory, address _elRewardFactory);
    event OperatorSlashChanged(address _oldOperatorSlashContract, address _operatorSlashContract);
    event MinStakeAmountChange(uint256 _oldMinStakeAmount, uint256 _minStakeAmount);

    LiquidStaking _liquidStaking;
    NETH _neth;
    VNFT _vnft;
    VaultManager _vaultManager;
    NodeOperatorRegistry _operatorRegistry;
    WithdrawOracle _withdrawOracle;
    DepositContract _depositContract;
    ELVault _vaultContract;
    ELVaultFactory _vaultFactoryContract;
    ConsensusVault _consensusVaultContract;
    address payable _consensusVaultContractAddr;
    OperatorSlash _operatorSlash;
    WithdrawalRequest _withdrawalRequest;
    NodeDaoTreasury _nodeDaoTreasury;
    HashConsensusWithTimer _consensus;
    LargeStaking _largeStaking;
    ELReward _elReward;
    ELRewardFactory _elRewardFactory;

    address _dao = DAO;
    address _daoValutAddress;
    address _rewardAddress = address(22);
    address _controllerAddress1 = address(33);
    address _controllerAddress2 = address(44);
    address _controllerAddress3 = address(55);
    address _owner = address(5);

    address _oracleMember1 = address(111);
    address _oracleMember2 = address(112);
    address _oracleMember3 = address(113);
    address _oracleMember4 = address(114);
    address _oracleMember5 = address(115);
    address[] _rewardAddresses1 = new address[] (1);
    address[] _rewardAddresses2 = new address[] (1);
    address[] _rewardAddresses3 = new address[] (1);


    uint256[] _ratios = new uint256[] 
    (1);

    function setUp() public {
        _rewardAddresses1[0] = address(55);
        _rewardAddresses2[0] = address(56);
        _rewardAddresses3[0] = address(57);

        _ratios[0] = 100;
        _liquidStaking = new LiquidStaking();

        _consensusVaultContract = new ConsensusVault();
        _consensusVaultContract.initialize(_dao, address(_liquidStaking));
        _consensusVaultContractAddr = payable(_consensusVaultContract);

        _nodeDaoTreasury = new NodeDaoTreasury(_dao);
        _daoValutAddress = address(_nodeDaoTreasury);

        _neth = new NETH();
        _neth.setLiquidStaking(address(_liquidStaking));

        _vnft = new VNFT();
        _vnft.initialize();
        _vnft.setLiquidStaking(address(_liquidStaking));

        _vaultContract = new ELVault();
        _vaultFactoryContract = new ELVaultFactory();
        _vaultFactoryContract.initialize(address(_vaultContract), address(_liquidStaking), _dao);

        _operatorRegistry = new NodeOperatorRegistry();
        _operatorRegistry.initialize(_dao, _daoValutAddress, address(_vaultFactoryContract), address(_vnft));
        vm.prank(_dao);
        _operatorRegistry.setNodeOperatorregistrySetting(
            address(0), address(0), address(_liquidStaking), address(0), address(0), address(0), 0, 0, 0
        );
        _vaultFactoryContract.setNodeOperatorRegistry(address(_operatorRegistry));

        _depositContract = new DepositContract();

        (_consensus, _withdrawOracle) = deployWithdrawOracleMock();
        vm.startPrank(_dao);
        _consensus.updateInitialEpoch(INITIAL_EPOCH);
        _consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        _consensus.addMember(MEMBER_1, 1);
        _consensus.addMember(MEMBER_2, 3);
        _consensus.addMember(MEMBER_3, 3);
        _consensus.addMember(MEMBER_4, 3);
        _withdrawOracle.setLiquidStaking(address(_liquidStaking));
        vm.stopPrank();

        _liquidStaking.initialize(
            _dao,
            _daoValutAddress,
            hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106",
            address(_operatorRegistry),
            address(_neth),
            address(_vnft),
            address(_withdrawOracle),
            address(_depositContract)
        );

        _operatorRegistry.registerOperator{value: 1.1 ether}(
            "one", _controllerAddress1, _owner , _rewardAddresses1, _ratios
        );

        assertEq(0.1 ether, _daoValutAddress.balance);
        vm.prank(_dao);
        _operatorRegistry.setTrustedOperator(1);
        _operatorRegistry.registerOperator{value: 1.1 ether}(
            "two", _controllerAddress2, _owner , _rewardAddresses2, _ratios
        );

        _operatorRegistry.registerOperator{value: 1.1 ether}(
            "three", _controllerAddress3 , address(6), _rewardAddresses3, _ratios
        );
        vm.prank(_dao);
        _operatorRegistry.setTrustedOperator(3);

        _vaultManager = new VaultManager();

        uint256[] memory _operatorIds = new uint256[](0);
        address[] memory _users = new address[](0);
        uint256[] memory __nethAmounts = new uint256[](0);

        _withdrawalRequest = new WithdrawalRequest();
        _withdrawalRequest.initialize(
            _dao, address(_liquidStaking), address(_vnft), address(_neth), address(_operatorRegistry), address(_vaultManager)
        );

        _operatorSlash = new OperatorSlash();
        _operatorSlash.initialize(
            _dao,
            address(_liquidStaking),
            address(_vnft),
            address(_operatorRegistry),
            address(_withdrawalRequest),
            address(_vaultManager),
            7200
        );

        vm.prank(_dao);
        _operatorRegistry.setNodeOperatorregistrySetting(
            address(0), address(0), address(0), address(0), address(_operatorSlash), address(0), 0, 0, 0
        );

        vm.prank(_dao);
        _liquidStaking.initializeV2(
            _operatorIds,
            _users,
            __nethAmounts,
            address(_consensusVaultContract),
            address(_vaultManager),
            address(_withdrawalRequest),
            address(_operatorSlash),
            address(_withdrawOracle)
        );

        _vaultManager.initialize(
            _dao,
            address(_liquidStaking),
            address(_vnft),
            address(_operatorRegistry),
            address(_withdrawOracle),
            address(_operatorSlash)
        );
        vm.prank(_dao);
        _vaultManager.setDaoElCommissionRate(300);

        uint256[] memory _resetVaultOperatorIds = new uint256[] (1);
        _resetVaultOperatorIds[0] = 1;

        assertEq(_operatorRegistry.defaultOperatorCommission(), 0);
        address operatorVaultAddr = _operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("========_operatorRegistry.initializeV2==========", operatorVaultAddr);
        vm.prank(_dao);
        _operatorRegistry.initializeV2(address(_vaultFactoryContract), address(_operatorSlash), _resetVaultOperatorIds);
        operatorVaultAddr = _operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("========_operatorRegistry.initializeV2==========", operatorVaultAddr);
        assertEq(_operatorRegistry.defaultOperatorCommission(), 2000);

        vm.prank(_dao);
        _operatorRegistry.setNodeOperatorregistrySetting(
            address(0), address(0), address(0), address(0), address(0), address(0), 700, 0, 0
        );

        assertEq(_operatorRegistry.defaultOperatorCommission(), 700);

        _elReward = new ELReward();
        _elRewardFactory = new ELRewardFactory();
        _elRewardFactory.initialize(address(_elReward), _dao);
        _largeStaking = new LargeStaking();
        _largeStaking.initialize(
            _dao,
            _daoValutAddress,
            address(_operatorRegistry),
            address(_operatorSlash), 
            address(_withdrawOracle),
            address(_elRewardFactory),
            address(_depositContract) 
        );
        vm.prank(_dao);
        _operatorRegistry.initializeV3(address(_largeStaking));
    }

    // function testLargeStake() public {
    //     vm.deal(address(111), 1000 ether);

    //     vm.expectRevert(abi.encodeWithSignature("InvalidWithdrawalCredentials()"));
    //     vm.prank(address(111));
    //     _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), true );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 0);

    //     vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
    //     vm.prank(address(111));
    //     _largeStaking.largeStake{value: 319 ether}(1, address(1111), address(1112), false );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 0);

    //     vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
    //     _largeStaking.largeStake{value: 2 ether}(2, address(1111), address(1112), false );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(2), 0);

    //     vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
    //     _largeStaking.largeStake{value: 2 ether}(2, address(1111), address(1112), true );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(2), 0);

    //     vm.expectRevert(abi.encodeWithSignature("OperatorNotFound()"));
    //     _largeStaking.largeStake{value: 320 ether}(999, address(1111), address(1112), false );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(999), 0);

    //     vm.expectRevert(abi.encodeWithSignature("RequireOperatorTrusted()"));
    //     _largeStaking.largeStake{value: 320 ether}(2, address(1111), address(1112), false );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(2), 0);

    //     vm.expectRevert(abi.encodeWithSignature("InvalidWithdrawalCredentials()"));
    //     _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 0);

    //     vm.expectRevert(abi.encodeWithSignature("InvalidWithdrawalCredentials()"));
    //     _largeStaking.largeStake{value: 320 ether}(1, address(0), address(1112), false );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 0);
        
    //     vm.deal(address(1112), 1 ether);
    //     vm.expectRevert(abi.encodeWithSignature("SharedRewardPoolNotOpened()"));
    //     _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), true );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 0);
        
    //     // successful test case
    //     vm.expectEmit(true, true, false, true);
    //     emit LargeStake(1, 0 , 320 ether, address(1111), address(1112), false);
    //     vm.prank(address(111));
    //     _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );

    //     // getOperatorValidatorCounts
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 10);
        
    //     ( bool isELRewardSharing, uint256 stakingId, uint256 operatorId, uint256 stakingAmount,
    //      uint256 alreadyStakingAmount, uint256 unstakeRequestAmount, uint256 unstakeAmount,
    //       address owner, bytes32 withdrawCredentials )
    //      = _largeStaking.largeStakingList(0) ; 

    //     // Access the individual components of the stakingInfo
    //     assertEq(isELRewardSharing , false);
    //     assertEq(operatorId , 1);
    //     assertEq(stakingId , 0);
    //     assertEq(stakingAmount , 320 ether);
    //     assertEq(alreadyStakingAmount , 0);
    //     assertEq(unstakeRequestAmount , 0);
    //     assertEq(unstakeAmount , 0);
    //     assertEq(owner , address(1111) );
    //     console.logBytes32(  withdrawCredentials );

    // } 

    // function testAppendLargeStake() public {

    //     vm.deal(address(1111), 1000 ether);
    //     vm.deal(address(1112), 1 ether);

    //     vm.prank(address(1111));
    //     _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 10);

    //     vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
    //     vm.prank(address(1111));
    //     _largeStaking.appendLargeStake{value: 319 ether}(0, address(1111), address(1112) );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 10);  

    //     vm.expectRevert(abi.encodeWithSignature("InvalidParameter()"));
    //     vm.prank(address(1111));
    //     _largeStaking.appendLargeStake{value: 320 ether}(0, address(1111), address(2222) );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 10);  

    //     _largeStaking.appendLargeStake{value: 320 ether}(0, address(1111), address(1112)  );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 20);

    //     _largeStaking.appendLargeStake{value: 320 ether}(0, address(1111), address(1112)  );
    //     assertEq(_largeStaking.getOperatorValidatorCounts(1), 30);

    // }

    //     function testLargeUnstake() public {
    //         vm.deal(address(1111), 320 ether);
    //         vm.prank(address(1111));
    //         vm.deal(address(1112), 1 ether);
    //         _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );
    //         assertEq(_largeStaking.getOperatorValidatorCounts(1), 10);

    //         vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
    //         vm.prank(address(1111));
    //         _largeStaking.largeUnstake(0, 16 ether );
    //         assertEq( address(1111).balance  , 0);

    //         // // successful test case
    //         vm.expectEmit(true, true, false, true);
    //         emit FastUnstake(0, 64 ether);
    //         vm.prank(address(1111));
    //         _largeStaking.largeUnstake(0, 64 ether );
    //         assertEq(_largeStaking.getOperatorValidatorCounts(1), 8);
    //         assertEq( address(1111).balance  ,  64 ether  );
    //         assertEq( address(1112).balance  ,  1 ether  );

    //         vm.expectEmit(true, true, false, true);
    //         emit FastUnstake(0, 128 ether);
    //         vm.prank(address(1111));
    //         _largeStaking.largeUnstake(0, 128 ether );
    //         assertEq( address(1111).balance  ,  192 ether  );

    //     }

    //     function _prepRegisterValidator() private returns(bytes memory){
    //         //  successful test case
    //         vm.deal(address(111), 1000 ether);
    //         vm.expectEmit(true, true, false, true);
    //         emit LargeStake(1, 0 , 320 ether, address(1111), address(1112), false);
    //         vm.deal(address(1112), 1 ether);
    //         vm.prank(address(111));
    //         _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );

    //         //   registerValidator
    //         bytes[] memory pubkeys = new bytes[](1);
    //         bytes[] memory signatures = new bytes[](1);
    //         bytes32[] memory depositDataRoots = new bytes32[](1);
    //         bytes memory pubkey =
    //             bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
    //         bytes memory sign = bytes(
    //             hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
    //         );
    //         bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
    //         pubkeys[0] = pubkey;
    //         signatures[0] = sign;
    //         depositDataRoots[0] = root;

    //         // _largeStaking  
    //         assertEq(_vnft.validatorExists(pubkey), false);
    //         vm.expectEmit(true, true, false, true);
    //         emit ValidatorRegistered(1, 0 , pubkey ) ;
    //         vm.prank(address(_controllerAddress1));
    //         _largeStaking.registerValidator(0, pubkeys, signatures, depositDataRoots);

    //         ( bool isELRewardSharing, uint256 stakingId, uint256 operatorId, uint256 stakingAmount,
    //         uint256 alreadyStakingAmount, uint256 unstakeRequestAmount, uint256 unstakeAmount,
    //         address owner, bytes32 withdrawCredentials )
    //         = _largeStaking.largeStakingList(0) ; 

    //         // Access the individual components of the stakingInfo
    //         assertEq(isELRewardSharing , false);
    //         assertEq(operatorId , 1);
    //         assertEq(stakingId , 0);
    //         assertEq(alreadyStakingAmount , 32 ether);
    //         assertEq(unstakeRequestAmount , 0);
    //         assertEq(unstakeAmount , 0);
    //         return pubkey ; 
    // }

    //     // migrateStake
    //    function testMigrateStake() public {
    //         bytes memory _pubKey =  _prepRegisterValidator();

    //         address _testControllerAddress1 = address(33);
    //         vm.deal(address(1112), 1 ether);
    //         // vm.expectEmit(true, true, false, true);
    //         // emit MigretaStake(1, 1, 64 ether, address(1111), false) ;
    //         vm.prank(_testControllerAddress1);
    //         bytes[] memory _pubkeys = new bytes[](1); 
    //         _pubkeys[0] = _pubKey;
    //         // bytes[] memory _validators = _largeStaking.validators(0, 0)   ; 
    //         // console.log("_largeStaking.validators(0, 0)"  );
    //         // console.logBytes( _validators);
    //         _largeStaking.migrateStake(address(1111), address(1112), false, _pubkeys );
    //    }

    //     function testAppendMigrateStake() public {
    //         bytes memory _pubKey =  _prepRegisterValidator();
    //         address _testControllerAddress1 = address(33);
    //         vm.prank(_testControllerAddress1);
    //         vm.deal(address(1112), 1 ether);
    //         vm.expectEmit(true, true, false, true);
    //         emit MigretaStake(1, 1, 32 ether ,address(1111), address(1112), false) ;
    //         bytes[] memory _pubkeys = new bytes[](1); 
    //         _pubkeys[0] = _pubKey;
    //         _largeStaking.migrateStake(address(1111), address(1112), false, _pubkeys );
    //         console.log("getOperatorValidatorCounts 1", _largeStaking.getOperatorValidatorCounts(0) );
    //     }

    //     function testRegisterValidator() public {

    //         //   registerValidator
    //         bytes[] memory pubkeys = new bytes[](1);
    //         bytes[] memory signatures = new bytes[](1);
    //         bytes32[] memory depositDataRoots = new bytes32[](1);
    //         bytes memory pubkey =
    //             bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
    //         bytes memory sign = bytes(
    //             hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
    //         );
    //         bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
    //         pubkeys[0] = pubkey;
    //         signatures[0] = sign;
    //         depositDataRoots[0] = root;

            
    //         //fail cases
    //         bytes[] memory pubkeys2 = new bytes[](2);
    //         bytes[] memory signatures2 = new bytes[](3);
    //         bytes32[] memory depositDataRoots2 = new bytes32[](2);

    //         vm.deal(address(1112), 1 ether);
    //         vm.expectRevert(abi.encodeWithSignature("InvalidParameter()"));
    //         vm.prank(address(_controllerAddress1));
    //         _largeStaking.registerValidator(0, pubkeys2, signatures2, depositDataRoots2);

    //         vm.expectRevert(abi.encodeWithSignature("RequireOperatorTrusted()"));
    //         vm.prank(address(3333));
    //         _largeStaking.registerValidator(0, pubkeys, signatures, depositDataRoots);
    //         assertEq(_largeStaking.getOperatorValidatorCounts(2), 0);



    //           //  successful test case
    //         vm.deal(address(111), 1000 ether);
    //         vm.expectEmit(true, true, false, true);
    //         emit LargeStake(1, 0 , 320 ether, address(1111), address(1112), false);
    //         vm.deal(address(1112), 1 ether);
    //         vm.prank(address(111));
    //         _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );

     

    //         // _largeStaking  
    //         assertEq(_vnft.validatorExists(pubkey), false);
    //         vm.expectEmit(true, true, false, true);
    //         emit ValidatorRegistered(1, 0 , pubkey ) ;
    //         vm.prank(address(_controllerAddress1));
    //         _largeStaking.registerValidator(0, pubkeys, signatures, depositDataRoots);

    //         ( bool isELRewardSharing, uint256 stakingId, uint256 operatorId, uint256 stakingAmount,
    //         uint256 alreadyStakingAmount, uint256 unstakeRequestAmount, uint256 unstakeAmount,
    //         address owner, bytes32 withdrawCredentials )
    //         = _largeStaking.largeStakingList(0) ; 

    //         // Access the individual components of the stakingInfo
    //         assertEq(isELRewardSharing , false);
    //         assertEq(operatorId , 1);
    //         assertEq(stakingId , 0);
    //         assertEq(alreadyStakingAmount , 32 ether);
    //         assertEq(unstakeRequestAmount , 0);
    //         assertEq(unstakeAmount , 0);
    //     }

        function testGetWithdrawCredentials()  public {
            console.log("testGetWithdrawCredentials: " );
            assertEq(_largeStaking.getWithdrawCredentials(address(3333)), 0x0100000000000000000000000000000000000000000000000000000000000d05 );
            console.logBytes32(  _largeStaking.getWithdrawCredentials(address(5555) ));
            assertEq(_largeStaking.getWithdrawCredentials(address(5555)), 0x01000000000000000000000000000000000000000000000000000000000015b3 );
        }

        function testReward()  public {
            vm.deal(address(1111), 320 ether);
            vm.deal(address(222), 320 ether);

            vm.deal(address(1112), 1 ether);
            vm.deal(address(2222), 1 ether);

            // successful test case
            // vm.expectEmit(true, true, false, true);
            // emit LargeStake(1, 0 , 320 ether, address(1111), address(1112), false);
            vm.prank(address(1111));
            _largeStaking.largeStake{value: 320 ether}(1, address(1111), address(1112), false );
            assertEq(_largeStaking.getOperatorValidatorCounts(1), 10);

            vm.prank(address(222));
            _largeStaking.largeStake{value: 320 ether}(3, address(2221), address(2222), false );
            assertEq(_largeStaking.getOperatorValidatorCounts(3), 10);
            // getOperatorValidatorCounts
            assertEq(_largeStaking.reward( 0 ), 0 );
            assertEq(_largeStaking.reward( 1 ), 0 );


            console.log("getRewardPoolInfo 1:  ");
            (uint256 operatorId1, address rewardPoolAddr1, uint256 rewards1) = 
            _largeStaking.getRewardPoolInfo(0);
            assertEq( operatorId1 , 1);
            // assertEq( rewardPoolAddr1 , 0x1a7420135e3551169cf51251e77c21ecab8fbff7);
            assertEq( rewards1 , 0 );
            console.log("operatorId1:  ", operatorId1);
            console.log("rewardPoolAddr1:  ", rewardPoolAddr1);
            console.log("rewards1:  ", rewards1) ;

            console.log("getRewardPoolInfo 3:  ");
            (uint256 operatorId3, address rewardPoolAddr3, uint256 rewards3) = 
            _largeStaking.getRewardPoolInfo(1);
            // assertEq( operatorId2 , 2);
            // assertEq( rewardPoolAddr1 , 0x325E7f6C6e236F87de24Ae8D6482B00c890EC4a9);
            // assertEq( rewards1 , 0 );
            console.log("operatorId3:  ", operatorId3);
            console.log("rewardPoolAddr3:  ", rewardPoolAddr3);
            console.log("rewards3:  ", rewards3) ;

            _largeStaking.settleElSharedReward(0) ;
            _largeStaking.settleElSharedReward(1) ;

            _largeStaking.settleElPrivateReward(0) ;
            _largeStaking.settleElPrivateReward(1) ;

            assertEq(_largeStaking.reward( 0 ), 0 );
            assertEq(_largeStaking.reward( 1 ), 0 );

            vm.prank(address(1111));
            vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
            _largeStaking.claimRewardsOfUser(0, address(1111), 322 ether);
            assertEq(_largeStaking.reward(0), 0 ether);

            vm.prank(address(4444));
            vm.expectRevert(abi.encodeWithSignature("PermissionDenied()"));
            _largeStaking.claimRewardsOfUser(0, address(1111), 66 ether);
            assertEq(_largeStaking.reward(0), 0 ether);

        }


}
