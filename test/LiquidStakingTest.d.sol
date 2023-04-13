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
import {WithdrawInfo, ExitValidatorInfo} from "src/library/ConsensusStruct.sol";
import "src/OperatorSlash.sol";
import "src/WithdrawalRequest.sol";

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
    error PermissionDenied();

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
    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;
    ERC20 erc20;

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

        consensusVaultContract = new ConsensusVault();
        consensusVaultContract.initialize(_dao, address(liquidStaking));
        consensusVaultContractAddr = payable(consensusVaultContract);

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
        operatorRegistry.setLiquidStaking(address(liquidStaking));
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

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

        vm.prank(_dao);
        liquidStaking.setOperatorCanLoanAmounts(32 ether);

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "one", _controllerAddress, address(4), _rewardAddresses, _ratios
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        vaultManager = new VaultManager();

        uint256[] memory _operatorIds = new uint256[](0);
        address[] memory _users = new address[](0);
        uint256[] memory _nethAmounts = new uint256[](0);

        withdrawalRequest = new WithdrawalRequest();
        withdrawalRequest.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(neth),
            address(operatorRegistry),
            address(withdrawalRequest),
            address(vaultManager)
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
        operatorRegistry.setOperatorSlashContract(address(operatorSlash));
        vm.prank(_dao);
        liquidStaking.initializeV2(
            _operatorIds,
            _users,
            _nethAmounts,
            address(consensusVaultContract),
            address(vaultManager),
            address(withdrawalRequest),
            address(operatorSlash)
        );

        vaultManager.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawOracle),
            address(operatorSlash)
        );
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

        // vm.expectRevert(0xdc0ca7f3); //revert RequireOperatorTrusted(); 
        // liquidStaking.stakeETH{value: 1 ether}(2);

        vm.expectRevert(0xae4207eb); //revert OperatorNotFound();//0xae4207eb
        vm.prank(address(2));
        liquidStaking.stakeETH{value: 1 ether}(13);

    }

    
    function testRegisterOperatorFailRequireCases() public {
        vm.prank(address(45));
        vm.deal(address(45), 22 ether);
        vm.expectRevert(0x5945ea56); // revert InsufficientAmount();
        operatorRegistry.registerOperator{value: 0.1 ether}(
            "three", address(_controllerAddress3), address(13), _rewardAddresses3, _ratios
        );
        vm.prank(address(45));
        vm.expectRevert(0xe481c269);
        operatorRegistry.registerOperator{value: 1.1 ether}(
            "four", address(_controllerAddress4), address(14), _rewardAddresses4, _ratios
        );
        vm.expectRevert(0x613970e0);
        string memory _longName = "123142141212131223123122112231231312323123142341";
        vm.prank(address(45));
        operatorRegistry.registerOperator{value: 1.1 ether}(
            _longName, address(_controllerAddress5), address(15), _rewardAddresses5, _ratios
        );

        vm.expectRevert(0xe481c269); //EMPTY_ADDRESS
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
        vm.expectRevert(0x8df3c4f5);// Invalid Ratio

        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testOperator1", _controllerAddress6, _owner6, _rewardAddresses6, _ratios6
        );
        vm.expectRevert(0x613970e0);

        uint256 operatorId2 = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testOperator2", _controllerAddress6, _owner6, _rewardAddresses6, _ratios
        );

    }

    function testConsensusVaultFailCases() public {
        vm.deal(address(consensusVaultContract), 100 ether);
        assertEq(100 ether, address(consensusVaultContract).balance);

        vm.expectRevert(0xe481c269); //revert PermissionDenied();
        vm.prank(address(liquidStaking));
        consensusVaultContract.transfer(50 ether, address(0));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(111));
        consensusVaultContract.setLiquidStaking(address(61));
        console.log("consensusVaultContract.owner(): ", consensusVaultContract.owner() );
        vm.expectRevert(0xe481c269); //revert InvalidAddr();
        consensusVaultContract.setLiquidStaking(address(0));
    }

    function testELVaultFactoryFailCases() public {

        vm.prank(address(vaultFactoryContract) );
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactoryContract.setNodeOperatorRegistry(address(0));

        vm.prank(address(vaultFactoryContract) );
        //Dao address invalid"
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactoryContract.setDaoAddress(address(0));

        uint256[] memory operatorIds = new uint256[](1);
        operatorIds[0] = 1 ;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 ;
        // vm.expectRevert(0x613970e0);  //revert InvalidParameter()
        // vm.prank(address(vaultManager) );
        // liquidStakingContract.reinvestClRewards(operatorIds, amounts); //
        // vm.expectRevert(        ); //revert PermissionDenied();
        // vm.prank(address(111) );
        // liquidStakingContract.reinvestClRewards(operatorIds, amounts); 


        uint256[] memory _exitTokenIds = new uint256[] (2);
        _exitTokenIds[0] = 0;
        _exitTokenIds[1] = 1;
        uint256[] memory _amounts = new uint256[] (1);
        _amounts[0] = 0.2 ether;

        // vm.prank(address(vaultManager));
        // vm.expectRevert(0x613970e0);
        // liquidStaking.reinvestElRewards(operatorIds, amounts);

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

    }

    function testAddSlashFundToStakePool() public {
        vm.deal(address(operatorSlash), 12 ether) ;
        assertEq(0 , liquidStaking.getOperatorPoolBalances(1));
        vm.prank(address(operatorSlash));
        liquidStaking.addSlashFundToStakePool{value : 1 ether }(1, 1 ether); 
        assertEq(1 ether, liquidStaking.getOperatorPoolBalances(1));   
        
        vm.prank(address(operatorSlash));
        liquidStaking.addSlashFundToStakePool{value : 1 ether }(1, 2 ether); 
        assertEq(3 ether, liquidStaking.getOperatorPoolBalances(1));       
    }    


        function testLargeWithdrawalUnstake() public {
            vm.deal(address(20), 100 ether) ;
            vm.prank(address(20));
            liquidStaking.stakeETH{value: 32 ether}(1);
            assertEq(0, vnft.balanceOf(address(20)));
            assertEq(32 ether, neth.balanceOf(address(20)));
            assertEq(0, vnft.balanceOf(address(liquidStaking)));
            assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
            assertEq(32 ether, liquidStaking.operatorPoolBalances(1));
            
            LiquidStaking.StakeInfo[] memory testStakeInfo1 = liquidStaking.getUnstakeQuota(address(20));
            assertEq(32 ether, testStakeInfo1[0].quota);   
           
            vm.prank(address(withdrawalRequest));
            liquidStaking.largeWithdrawalUnstake(1, address(20) ,32 ether);            
            LiquidStaking.StakeInfo[] memory testStakeInfo2 = liquidStaking.getUnstakeQuota(address(20));
            assertEq(0 , testStakeInfo2[0].quota);   
    }    

        function testLargeWithdrawalBurnNeth() public {
            vm.deal(address(withdrawalRequest), 100 ether) ;
            vm.prank(address(withdrawalRequest));
            liquidStaking.stakeETH{value: 20 ether}(1);
            assertEq(20 ether, neth.balanceOf(address(withdrawalRequest)));
            vm.prank(address(withdrawalRequest));
            liquidStaking.largeWithdrawalBurnNeth(1 ether);
            assertEq(19 ether, neth.balanceOf(address(withdrawalRequest)));
            vm.prank(address(withdrawalRequest));
            liquidStaking.largeWithdrawalBurnNeth(5 ether);
            assertEq(14 ether, neth.balanceOf(address(withdrawalRequest)));
        }   

}
