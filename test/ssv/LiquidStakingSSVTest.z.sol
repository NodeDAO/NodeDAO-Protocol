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
import "src/StakingManager.sol";
import "src/ssv/SSVCluster.sol";
import "src/ssv/SSVManager.sol";
import "src/interfaces/ISSV.sol";
import "test/ssv/modules/SSVClusters.sol";
import "test/ssv/modules/SSVOperators.sol";
import "test/ssv/modules/SSVViews.sol";
import "test/ssv/modules/SSVDAO.sol";
import "test/ssv/mocks/SSVTokenMock.sol";
import "test/ssv/SSVNetwork.sol";
import "./interfaces/ISSVClusters.sol";
import "./interfaces/ISSVOperators.sol";
import "./interfaces/ISSVDAO.sol";
import "./interfaces/ISSVViews.sol";

// forge test --match-path  test/LiquidStakingSSVTest.z.sol
contract LiquidStakingSSVTest is Test, MockMultiOracleProvider {
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
    StakingManager stakingManager;
    SSVManager ssvManager;
    SSVNetwork ssvNetwork;
    SSVOperators ssvOperators;
    SSVClusters ssvClusters;
    SSVTokenMock ssvToken;
    SSVViews ssvViews;
    SSVDAO ssvDao;

    address _dao = DAO;
    address _daoValutAddress;
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
    address _owner = address(5);
    address _oracleMember1 = address(11);
    address _oracleMember2 = address(12);
    address _oracleMember3 = address(13);
    address _oracleMember4 = address(14);
    address _oracleMember5 = address(15);
    address[] _rewardAddresses = new address[] (1);
    uint256[] _ratios = new uint256[] (1);

    function setUp() public {
        _rewardAddresses[0] = address(5);
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

        consensus.addReportProcessor(address(withdrawOracle), 1);
        consensus.addReportProcessor(address(reportProcessor1), 1);

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
        vaultManager.setVaultManagerSetting(300, 0, address(0), address(0), address(0), address(0));

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
            address(0), address(0), address(0), address(0), address(0), address(0), 700, 0, 0
        );

        assertEq(operatorRegistry.defaultOperatorCommission(), 700);

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
        operatorRegistry.initializeV3(address(largeStaking));

        vm.prank(_dao);
        largeStaking.setLargeStakingSetting(
            address(0), address(0), 300, 0, 0, address(0), address(0), address(0), address(0)
        );
        operatorSlash.initializeV2(address(largeStaking));
        vaultManager.initializeV2(address(neth));

        // init ssv
        ssvOperators = new SSVOperators();
        ssvClusters = new SSVClusters();
        ssvToken = new SSVTokenMock();
        ssvViews = new SSVViews();
        ssvDao = new SSVDAO();
        ssvNetwork = new SSVNetwork();
        ssvNetwork.initialize(
            IERC20(ssvToken),
            ISSVOperators(ssvOperators),
            ISSVClusters(ssvClusters),
            ISSVDAO(ssvDao),
            ISSVViews(ssvViews),
            10,
            1000000000000000000,
            500,
            500,
            500,
            500
        );

        ssvNetwork.updateMaximumOperatorFee(1000000000000000);

        SSVCluster ssvCluster = new SSVCluster();
        ssvManager = new SSVManager();

        stakingManager = new StakingManager();
        stakingManager.initialize(_dao, address(operatorRegistry), address(liquidStaking), address(ssvManager));

        ssvManager.initialize(
            address(ssvCluster),
            _dao,
            address(ssvNetwork),
            address(ssvToken),
            address(operatorRegistry),
            address(stakingManager)
        );

        liquidStaking.initializeV3(address(stakingManager));
    }

    function testStakeETH() public {
        vm.expectEmit(true, true, false, true);
        emit EthStake(1, address(20), 1 ether, 1 ether);
        vm.deal(address(20), 2 ether);

        console.log("rate: 1", liquidStaking.getNethOut(1 ether));
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 1 ether}(1);
        console.log("rate: 2", liquidStaking.getNethOut(1 ether));
        vm.deal(address(21), 2 ether);

        console.log("rate: 3 ", liquidStaking.getNethOut(1 ether));
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 1 ether}(1);
        console.log("balance: 21", neth.balanceOf(address(21)));
        console.log("rate: 4 ", liquidStaking.getNethOut(1 ether));

        vm.deal(address(23), 5 ether);

        console.log("rate: 4 ", liquidStaking.getNethOut(3 ether));
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 3 ether}(1);
        console.log("balance: 23", neth.balanceOf(address(23)));

        assertEq(liquidStaking.operatorPoolBalances(1), 5 ether);
    }

    function testStakeETHWithDepositFee() public {
        vm.deal(address(20), 2 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 1 ether}(1);
        console.log("rate: 2", liquidStaking.getNethOut(1 ether));
        vm.deal(address(21), 2 ether);

        console.log("rate: 3 ", liquidStaking.getNethOut(1 ether));
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 1 ether}(1);
        console.log("balance: 21", neth.balanceOf(address(21)));
        console.log("rate: 4 ", liquidStaking.getNethOut(1 ether));

        vm.deal(address(23), 5 ether);

        console.log("rate: 4 ", liquidStaking.getNethOut(3 ether));
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 3 ether}(1);
        console.log("balance: 23", neth.balanceOf(address(23)));

        assertEq(liquidStaking.operatorPoolBalances(1), 5 ether);

        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(1000);

        vm.deal(address(24), 500 ether);
        liquidStaking.stakeETH{value: 500 ether}(1);
    }

    function testStakeNFT() public {
        vm.expectEmit(true, true, false, true);
        emit NftStake(1, address(20), 10);
        vm.prank(address(20));
        vm.deal(address(20), 330 ether);
        vm.roll(10000);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1 wei);
        liquidStaking.stakeNFT{value: 320 ether}(1, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        assertEq(10, vnft.balanceOf(address(20)));

        assertEq(vnft.operatorEmptyNftIndex(1), 0);

        assertEq(vnft.operatorEmptyNfts(1, 0), 0);
        assertEq(vnft.operatorEmptyNfts(1, 1), 1);
        assertEq(vnft.operatorEmptyNfts(1, 2), 2);
        assertEq(vnft.operatorEmptyNfts(1, 3), 3);
        assertEq(vnft.operatorEmptyNfts(1, 4), 4);
        assertEq(vnft.operatorEmptyNfts(1, 5), 5);
        assertEq(vnft.operatorEmptyNfts(1, 6), 6);
        assertEq(vnft.operatorEmptyNfts(1, 7), 7);
        assertEq(vnft.operatorEmptyNfts(1, 8), 8);
        assertEq(vnft.operatorEmptyNfts(1, 9), 9);

        uint256 operatorId;
        uint256 initHeight;
        bytes memory pubkey;
        (operatorId, initHeight, pubkey) = vnft.validators(0);

        assertEq(operatorId, 1);
        assertEq(pubkey, bytes(""));
        assertEq(initHeight, 10000);
        bytes memory userWithdrawalCredentials;
        userWithdrawalCredentials = vnft.getUserNftWithdrawalCredentialOfTokenId(0);
        console.logBytes(userWithdrawalCredentials);
        assertEq(userWithdrawalCredentials, hex"010000000000000000000000f5ade6b61ba60b8b82566af0dfca982169a470dc");
    }

    function testFailedStakeNFT2() public {
        vm.prank(address(20));
        vm.roll(10000);

        liquidStaking.stakeNFT{value: 0 ether}(1, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(0, neth.balanceOf(address(liquidStaking)));
    }

    function testGetExchangeRate() public {
        vm.roll(10000);

        vm.prank(address(20));
        vm.deal(address(20), 330 ether);
        liquidStaking.stakeETH{value: 30 ether}(1);

        vm.prank(address(21));
        vm.deal(address(21), 330 ether);
        liquidStaking.stakeETH{value: 31 ether}(1);

        vm.prank(address(22));
        vm.deal(address(22), 330 ether);
        liquidStaking.stakeETH{value: 3.2 ether}(1);

        vm.prank(address(23));
        vm.deal(address(23), 330 ether);
        liquidStaking.stakeETH{value: 0.32 ether}(1);

        vm.prank(address(24));
        vm.deal(address(24), 330 ether);
        liquidStaking.stakeETH{value: 0.1457 ether}(1);

        vm.prank(address(25));
        vm.deal(address(25), 330 ether);
        liquidStaking.stakeETH{value: 0.325878 ether}(1);

        vm.prank(address(26));
        vm.deal(address(26), 330 ether);
        liquidStaking.stakeETH{value: 30.09987 ether}(1);

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);
    }

    function testAll() public {
        vm.roll(10000);

        // test stakeETH
        vm.deal(address(20), 33 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 32 ether}(1);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(32 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));

        vm.deal(address(21), 32 ether);
        vm.prank(address(21));
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        assertEq(1, vnft.balanceOf(address(21)));
        assertEq(0, neth.balanceOf(address(21)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));

        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("operatorVaultAddr: ", operatorVaultAddr);
        console.log("operatorVaultImpl: ", address(vaultContract));

        vm.deal(address(operatorVaultAddr), 1 ether);

        vm.deal(address(22), 32 ether);
        vm.prank(address(22));
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        assertEq(1, vnft.balanceOf(address(22)));
        assertEq(0, neth.balanceOf(address(22)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(64 ether, liquidStaking.operatorNftPoolBalances(1));

        assertEq(address(21).balance, 0);
        assertEq(address(22).balance, 0);

        uint256[] memory operatorIds = new uint256[] (1);
        operatorIds[0] = 1;
        vaultManager.settleAndReinvestElReward(operatorIds);

        assertEq(2, vnft.getEmptyNftCounts());
        assertEq(0, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(0, vnft.getActiveNftCountsOfOperator(1));

        vm.prank(address(liquidStaking));
        vnft.whiteListMint(
            bytes("01"), hex"010000000000000000000000f5ade6b61ba60b8b82566af0dfca982169a470dc", address(100), 1
        );
        vm.prank(address(liquidStaking));
        vnft.whiteListMint(
            bytes("02"), hex"010000000000000000000000f5ade6b61ba60b8b82566af0dfca982169a470dc", address(100), 1
        );
        assertEq(0, vnft.balanceOf(address(100)));
        assertEq(vnft.validatorOf(0), bytes("01"));
        assertEq(vnft.validatorOf(1), bytes("02"));
        assertEq(2, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(2, vnft.getActiveNftCountsOfOperator(1));

        // no registry validator, so 64 eth
        assertEq(64 ether, liquidStaking.operatorNftPoolBalances(1));

        vm.roll(20000);

        uint256[] memory tokenIds = new uint256[] (1);

        vaultManager.settleAndReinvestElReward(operatorIds);

        tokenIds[0] = 0;
        assertEq(10000, vnft.getUserNftGasHeight(tokenIds)[0]);
        vaultManager.claimRewardsOfUser(tokenIds);
        tokenIds[0] = 1;
        assertEq(10000, vnft.getUserNftGasHeight(tokenIds)[0]);
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(address(22).balance, 0.45 ether);
        assertEq(address(21).balance, 0.45 ether);

        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));

        vm.deal(address(23), 33 ether);
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 32 ether}(1);
        assertEq(0, vnft.balanceOf(address(23)));
        assertEq(32 ether, neth.balanceOf(address(23)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(64 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);

        assertEq(32 ether, neth.balanceOf(address(23)));
        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(0, vnft.getEmptyNftCounts());
        assertEq(2, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(2, vnft.getActiveNftCountsOfOperator(1));

        vm.deal(address(24), 32 ether);
        vm.prank(address(24));
        vm.deal(0x00dFaaE92ed72A05bC61262aA164f38B5626e106, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0x00dFaaE92ed72A05bC61262aA164f38B5626e106);
        assertEq(1, vnft.balanceOf(address(24)));
        assertEq(0, neth.balanceOf(address(24)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(1, vnft.getEmptyNftCounts());
        assertEq(2, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(2, vnft.getActiveNftCountsOfOperator(1));

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

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
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(64 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(64 ether, liquidStaking.operatorNftPoolBalances(1)); // 62 + 32 - 32

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 2); // already 0, 1

        pubkey =
            bytes(hex"83d3693fb9da8aed60a5c94c51927158d6e3a4d36fa6982ba2c87f83260329baf08f93d000f9261911420a9c0f0eb022");
        sign = bytes(
            hex"b0e13147956deb0b188e79de8181d0f9f216a43cf8fe0435c5c919da0182400e440ff6ba11d1c2ec12bec824200d9d07130d53260e8f03d7292af14e909731435ffe5beb4e97f7e97e55cd555e99e23de6dbb5618a40bd26b7537b9cd4104370"
        );
        root = bytes32(hex"f497234b67c6258b9cd46627adb7a88a26a5b48cbe90ee3bdb24bf9c559a0595");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(1, vnft.balanceOf(address(liquidStaking)));
        assertEq(0, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 3);
        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
    }

    function testRegisterValidator() public {
        vm.roll(10000);

        vm.deal(address(20), 55 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 50 ether}(1);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(50 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(50 ether, liquidStaking.operatorPoolBalances(1));

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

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
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
    }

    function testFailPause() public {
        vm.prank(_dao);
        liquidStaking.pause();

        vm.deal(address(20), 55 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 50 ether}(1);
    }

    function testPause() public {
        vm.prank(_dao);
        liquidStaking.pause();
        vm.prank(_dao);
        liquidStaking.unpause();
        vm.deal(address(20), 55 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 50 ether}(1);
    }

    function testFailRegisterOperator() public {
        address _controllerAddress = address(40);
        address _owner = address(41);
        operatorRegistry.registerOperator{value: 1.1 ether}( // name: Invalid length
        "33woqwertyuuoionkonkonkonkonkonkd", _controllerAddress, _owner, _rewardAddresses, _ratios);
    }

    function checkOperator(
        uint256 operatorId,
        bool _trusted,
        string memory _name,
        address _controllerAddr,
        address _owner
    ) public {
        bool trusted;
        string memory name;
        address owner;
        address controllerAddress;
        address vaultContractAddress;
        (trusted, name, owner, controllerAddress, vaultContractAddress) =
            operatorRegistry.getNodeOperator(operatorId, true);
        assertEq(trusted, _trusted);
        assertEq(name, _name);
        assertEq(owner, _owner);
        assertEq(controllerAddress, _controllerAddr);
        console.log("vaultContractAddress: ", vaultContractAddress);
    }

    function testNodeOperatorRegistry() public {
        address _controllerAddress = address(40);
        address _owner = address(41);
        address _to = address(45);
        address[] memory _rewardAddresses2 = new address[] (3);
        uint256[] memory _ratios2 = new uint256[] (3);
        _rewardAddresses2[0] = address(42);
        _rewardAddresses2[1] = address(43);
        _rewardAddresses2[2] = address(44);
        _ratios2[0] = 70;
        _ratios2[1] = 20;
        _ratios2[2] = 10;
        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test", _controllerAddress, _owner, _rewardAddresses2, _ratios2
        );

        assertEq(false, operatorRegistry.isQuitOperator(operatorId));

        checkOperator(operatorId, false, "test", _controllerAddress, _owner);
        (address[] memory rewardAddresses, uint256[] memory ratios) =
            operatorRegistry.getNodeOperatorRewardSetting(operatorId);
        assertEq(rewardAddresses[0], _rewardAddresses2[0]);
        assertEq(rewardAddresses[1], _rewardAddresses2[1]);
        assertEq(rewardAddresses[2], _rewardAddresses2[2]);
        assertEq(ratios[0], _ratios2[0]);
        assertEq(ratios[1], _ratios2[1]);
        assertEq(ratios[2], _ratios2[2]);

        operatorRegistry.deposit{value: 5 ether}(operatorId);
        uint256 pledgeBalance = 0;
        uint256 requirBalance = 0;
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(operatorId);
        assertEq(6 ether, pledgeBalance);
        assertEq(1 ether, requirBalance);
        assertEq(false, operatorRegistry.isQuitOperator(operatorId));
        vm.prank(_owner);
        operatorRegistry.withdrawOperator(operatorId, 1 ether, _to);
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(operatorId);
        assertEq(5 ether, pledgeBalance);
        assertEq(1 ether, requirBalance);
        assertEq(_to.balance, 1 ether);

        assertEq(false, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(0, operatorRegistry.isTrustedOperatorOfControllerAddress(_controllerAddress));
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId);
        assertEq(true, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(2, operatorRegistry.isTrustedOperatorOfControllerAddress(_controllerAddress));

        vm.prank(_dao);
        operatorRegistry.setBlacklistOperator(operatorId);
        assertEq(false, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(0, operatorRegistry.isTrustedOperatorOfControllerAddress(_controllerAddress));

        vm.prank(_dao);
        operatorRegistry.removeBlacklistOperator(operatorId);
        assertEq(true, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(2, operatorRegistry.isTrustedOperatorOfControllerAddress(_controllerAddress));

        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(operatorId);
        assertEq(5 ether, pledgeBalance);
        vm.prank(_owner);
        operatorRegistry.withdrawOperator(operatorId, 1 ether, _to);
        assertEq(_to.balance, 2 ether);
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(operatorId);
        assertEq(4 ether, pledgeBalance);

        _rewardAddresses = new address[] (0);
        _ratios = new uint256[] (0);
        vm.prank(_owner);
        operatorRegistry.setOperatorSetting(operatorId, "test2", address(0), _rewardAddresses, _ratios);
        checkOperator(operatorId, true, "test2", address(40), _owner);

        _rewardAddresses2[0] = address(45);
        _rewardAddresses2[1] = address(46);
        _rewardAddresses2[2] = address(47);
        _ratios2[0] = 50;
        _ratios2[1] = 30;
        _ratios2[2] = 20;

        vm.prank(_owner);
        operatorRegistry.setOperatorSetting(operatorId, "", address(0), _rewardAddresses2, _ratios2);
        (address[] memory rewardAddresses3, uint256[] memory ratios3) =
            operatorRegistry.getNodeOperatorRewardSetting(operatorId);
        assertEq(rewardAddresses3[0], _rewardAddresses2[0]);
        assertEq(rewardAddresses3[1], _rewardAddresses2[1]);
        assertEq(rewardAddresses3[2], _rewardAddresses2[2]);
        assertEq(ratios3[0], _ratios2[0]);
        assertEq(ratios3[1], _ratios2[1]);
        assertEq(ratios3[2], _ratios2[2]);

        vm.prank(_owner);
        operatorRegistry.setOperatorSetting(operatorId, "", address(48), _rewardAddresses, _ratios);
        checkOperator(operatorId, true, "test2", address(48), _owner);
        assertEq(0, operatorRegistry.isTrustedOperatorOfControllerAddress(address(40)));
        assertEq(2, operatorRegistry.isTrustedOperatorOfControllerAddress(address(48)));

        vm.prank(_owner);
        operatorRegistry.setNodeOperatorOwnerAddress(operatorId, address(49));
        _owner = address(49);
        checkOperator(operatorId, true, "test2", address(48), _owner);

        console.log("getNodeOperatorVaultContract", operatorRegistry.getNodeOperatorVaultContract(operatorId));

        vm.prank(_owner);
        operatorRegistry.withdrawOperator(operatorId, 3 ether, _to);
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(operatorId);
        assertEq(1 ether, pledgeBalance);
        assertEq(_to.balance, 5 ether);

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(50), address(0), address(0), address(0), address(0), address(0), 0, 0, 0
        );
        assertEq(operatorRegistry.dao(), address(50));
        _dao = address(50);

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(51), address(0), address(0), address(0), address(0), 0, 0, 0
        );
        assertEq(operatorRegistry.daoVaultAddress(), address(51));

        assertEq(operatorRegistry.registrationFee(), 0.1 ether);
        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(0), address(0), 0, 1 ether, 0
        );
        assertEq(operatorRegistry.registrationFee(), 1 ether);

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(0), address(0), 0, 0, 1000000
        );
        assertEq(1000000, operatorRegistry.permissionlessBlockNumber());

        assertEq(true, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(true, operatorRegistry.isTrustedOperator(1));

        vm.prank(_dao);
        operatorRegistry.removeTrustedOperator(operatorId);
        vm.prank(_dao);
        operatorRegistry.removeTrustedOperator(1);
        assertEq(false, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(false, operatorRegistry.isTrustedOperator(1));

        vm.roll(999999);
        assertEq(false, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(false, operatorRegistry.isTrustedOperator(1));
        vm.roll(1000000);
        assertEq(true, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(true, operatorRegistry.isTrustedOperator(1));

        assertEq(false, operatorRegistry.isQuitOperator(operatorId));
        vm.prank(_owner);
        operatorRegistry.quitOperator(operatorId, _to);
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(operatorId);
        assertEq(0 ether, pledgeBalance);
        assertEq(1 ether, requirBalance);
        assertEq(_to.balance, 6 ether);
        assertEq(true, operatorRegistry.isQuitOperator(operatorId));
    }

    function testSetPermissionlessBlockNumber() public {
        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(0), address(0), 0, 0, 1000000
        );

        assertEq(1000000, operatorRegistry.permissionlessBlockNumber());
    }

    function testConsensusVault() public {
        consensusVaultContractAddr.transfer(100 ether);
        assertEq(100 ether, address(consensusVaultContract).balance);

        vm.prank(address(liquidStaking));
        consensusVaultContract.transfer(50 ether, address(60));
        assertEq(50 ether, address(consensusVaultContract).balance);
        assertEq(50 ether, address(60).balance);

        consensusVaultContract.setLiquidStaking(address(61));
        assertEq(consensusVaultContract.liquidStakingContractAddress(), address(61));
    }

    function testELVaultFactory() public {
        vaultFactoryContract.setNodeOperatorRegistry(address(70));
        assertEq(vaultFactoryContract.nodeOperatorRegistryAddress(), address(70));

        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));
        vm.prank(address(operatorRegistry));
        address vaultAddress = vaultFactoryContract.create(2);
        console.log(vaultAddress);
    }

    function testVaultManager() public {
        vm.roll(100);
        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testELVault", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
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
        vm.prank(address(_controllerAddress3));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        address vaultContractAddress;
        (,,,, vaultContractAddress) = operatorRegistry.getNodeOperator(operatorId, false);

        assertEq(address(vaultContractAddress).balance, 0);
        payable(vaultContractAddress).transfer(10 ether);
        assertEq(address(vaultContractAddress).balance, 10 ether);

        assertEq(32 ether, liquidStaking.operatorPoolBalances(operatorId));
        vm.roll(200);

        // registerValidator 2
        pubkey =
            bytes(hex"83d3693fb9da8aed60a5c94c51927158d6e3a4d36fa6982ba2c87f83260329baf08f93d000f9261911420a9c0f0eb022");
        sign = bytes(
            hex"b0e13147956deb0b188e79de8181d0f9f216a43cf8fe0435c5c919da0182400e440ff6ba11d1c2ec12bec824200d9d07130d53260e8f03d7292af14e909731435ffe5beb4e97f7e97e55cd555e99e23de6dbb5618a40bd26b7537b9cd4104370"
        );
        root = bytes32(hex"f497234b67c6258b9cd46627adb7a88a26a5b48cbe90ee3bdb24bf9c559a0595");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress3));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(0 ether, liquidStaking.operatorPoolBalances(operatorId)); // no reinvest

        assertEq(address(vaultContractAddress).balance, 10 ether);

        uint256[] memory operatorIds = new uint256[] (1);
        operatorIds[0] = operatorId;
        vaultManager.settleAndReinvestElReward(operatorIds);
        assertEq(9 ether, liquidStaking.operatorPoolBalances(operatorId)); // reinvest
        assertEq(vaultManager.daoRewardsMap(operatorId), 0.3 ether);
        assertEq(vaultManager.operatorRewardsMap(operatorId), 0.7 ether);

        assertEq(address(_daoValutAddress).balance, 0.2 ether); // registerOperator * 2 = 0.1 * 2

        vaultManager.claimRewardsOfOperator(operatorId);
        vaultManager.claimRewardsOfDao(operatorIds);

        assertEq(address(vaultContractAddress).balance, 0 ether);

        assertEq(address(_daoValutAddress).balance, 0.5 ether); // 0.2 + 0.3
        assertEq(0.49 ether, _rewardAddresses3[0].balance); // 0.7 * 0.7
        assertEq(0.14 ether, _rewardAddresses3[1].balance); // 0.7 * 0.2
        assertEq(0.07 ether, _rewardAddresses3[2].balance); // 0.7 * 0.1

        assertEq(64 ether, neth.totalSupply());
        assertEq(73 ether, liquidStaking.getTotalEthValue()); // 64 ether + 9 ether

        uint256 eth2NethRate = uint256(1 ether) * uint256(64 ether) / uint256(73 ether);

        console.log("==========eth2NethRate=============", eth2NethRate);
        console.log("==========getNethOut=============", liquidStaking.getNethOut(1 ether));
        console.log("==========getEthOut=============", liquidStaking.getEthOut(1 ether));
        console.log("==========getExchangeRate=============", liquidStaking.getExchangeRate());

        assertEq(eth2NethRate, liquidStaking.getNethOut(1 ether));

        assertEq(2, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        // UserNft
        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(operatorId, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(2, vnft.balanceOf(address(liquidStaking)));
        assertEq(9 ether, liquidStaking.operatorPoolBalances(operatorId));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(operatorId));

        uint256 nethAmount = uint256(32 ether) * uint256(64 ether) / uint256(73 ether);
        console.log("==========nethAmount=============", nethAmount);
        assertEq(nethAmount, liquidStaking.getNethOut(32 ether));
        console.log("==========getNethOut=============", liquidStaking.getNethOut(32 ether));
        assertEq(0, neth.balanceOf(address(liquidStaking)));

        vm.roll(300);

        // registerValidator 3
        pubkey =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(9 ether, liquidStaking.operatorPoolBalances(operatorId));
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress3));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(0 ether, liquidStaking.operatorNftPoolBalances(operatorId));

        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(2, vnft.balanceOf(address(liquidStaking)));
        assertEq(9 ether, liquidStaking.operatorPoolBalances(operatorId));

        // transfer rewards
        assertEq(address(vaultContractAddress).balance, 0);
        payable(vaultContractAddress).transfer(10 ether);
        assertEq(address(vaultContractAddress).balance, 10 ether);

        vm.roll(400);

        vaultManager.settleAndReinvestElReward(operatorIds);

        assertEq(15 ether, liquidStaking.operatorPoolBalances(operatorId)); // 9 + 6 eth (6 = 2/3 * 9)
        assertEq(vaultManager.daoRewardsMap(operatorId), 0.3 ether);
        assertEq(vaultManager.operatorRewardsMap(operatorId), 0.7 ether);
        uint256[] memory tokenIds = new uint256[] (1);
        tokenIds[0] = 2;
        assertEq(3 ether, vaultManager.rewards(tokenIds)[0]);

        vaultManager.claimRewardsOfOperator(operatorId);
        vaultManager.claimRewardsOfDao(operatorIds);

        assertEq(address(vaultContractAddress).balance, 3 ether);

        assertEq(address(_daoValutAddress).balance, 0.8 ether); // 0.2 + 0.3 + 0.3
        assertEq(0.98 ether, address(70).balance); // 0.7 * 0.7 + 0.7 * 0.7
        assertEq(0.28 ether, address(71).balance); // 0.7 * 0.2 + 0.7 * 0.2
        assertEq(0.14 ether, address(72).balance); // 0.7 * 0.1 + 0.7 * 0.1

        assertEq(0, address(74).balance);
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(400, vnft.getUserNftGasHeight(tokenIds)[0]);

        assertEq(3 ether, address(74).balance);

        vm.roll(500);
        // transfer rewards
        assertEq(address(vaultContractAddress).balance, 0);
        payable(vaultContractAddress).transfer(10 ether);
        assertEq(address(vaultContractAddress).balance, 10 ether);

        vaultManager.settleAndReinvestElReward(operatorIds);
        assertEq(address(vaultContractAddress).balance, 4 ether);

        assertEq(21 ether, liquidStaking.operatorPoolBalances(operatorId)); // 9 + 6 + 6 eth (6 = 2/3 * 9)
        assertEq(vaultManager.daoRewardsMap(operatorId), 0.3 ether);
        assertEq(vaultManager.operatorRewardsMap(operatorId), 0.7 ether);

        assertEq(3 ether, vaultManager.rewards(tokenIds)[0]);

        vaultManager.claimRewardsOfOperator(operatorId);
        vaultManager.claimRewardsOfDao(operatorIds);

        assertEq(address(vaultContractAddress).balance, 3 ether);

        assertEq(address(_daoValutAddress).balance, 1.1 ether); // 0.2 + 0.3 + 0.3 + 0.3
        assertEq(1.47 ether, address(70).balance); // 0.7 * 0.7 + 0.7 * 0.7 + 0.7 * 0.7
        assertEq(0.42 ether, address(71).balance); // 0.7 * 0.2 + 0.7 * 0.2 + 0.7 * 0.2
        assertEq(0.21 ether, address(72).balance); // 0.7 * 0.1 + 0.7 * 0.1 + 0.7 * 0.1

        assertEq(3 ether, address(74).balance);
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(6 ether, address(74).balance);
    }

    function testAssignBlacklistOperator() public {
        vm.roll(100);
        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test1", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        uint256 operatorId2 = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test2", address(81), _owner3, _rewardAddresses3, _ratios3
        );

        uint256 operatorId3 = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test3", address(82), _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId);
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId2);

        vm.deal(address(73), 100 ether);
        vm.prank(address(73));
        liquidStaking.stakeETH{value: 64 ether}(operatorId);
        assertEq(64 ether, liquidStaking.operatorPoolBalances(operatorId));

        vm.prank(_dao);
        operatorRegistry.setBlacklistOperator(operatorId);
        assertEq(true, operatorRegistry.isBlacklistOperator(operatorId));
        liquidStaking.assignOperator(operatorId, operatorId2);
        assertEq(0 ether, liquidStaking.operatorPoolBalances(operatorId));
        assertEq(64 ether, liquidStaking.operatorPoolBalances(operatorId2));
        assertEq(0, liquidStaking.reAssignRecords(operatorId));
    }

    function testAssignQuitOperator() public {
        vm.roll(100);
        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test1", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        uint256 operatorId2 = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test2", address(81), _owner3, _rewardAddresses3, _ratios3
        );

        uint256 operatorId3 = operatorRegistry.registerOperator{value: 1.1 ether}(
            "test3", address(82), _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId);
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId2);

        vm.deal(address(73), 100 ether);
        vm.prank(address(73));
        liquidStaking.stakeETH{value: 64 ether}(operatorId);
        assertEq(64 ether, liquidStaking.operatorPoolBalances(operatorId));

        vm.prank(_owner3);
        operatorRegistry.quitOperator(operatorId, address(100));

        liquidStaking.assignOperator(operatorId, operatorId2);
        assertEq(0 ether, liquidStaking.operatorPoolBalances(operatorId));
        assertEq(64 ether, liquidStaking.operatorPoolBalances(operatorId2));
        assertEq(operatorId2, liquidStaking.reAssignRecords(operatorId));
    }

    function testSlashOperator() public {
        vm.roll(100);

        vm.deal(address(24), 32 ether);
        vm.prank(address(24));
        vm.deal(0x00dFaaE92ed72A05bC61262aA164f38B5626e106, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0x00dFaaE92ed72A05bC61262aA164f38B5626e106);
        assertEq(1, vnft.balanceOf(address(24)));
        assertEq(0, neth.balanceOf(address(24)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(1, vnft.getEmptyNftCounts());
        assertEq(0, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(0, vnft.getActiveNftCountsOfOperator(1));

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

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
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(0, vnft.getEmptyNftCounts());
        assertEq(1, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(1, vnft.getActiveNftCountsOfOperator(1));

        uint256[] memory _exitTokenIds = new uint256[] (1);
        _exitTokenIds[0] = 0;
        uint256[] memory _amounts = new uint256[] (1);
        _amounts[0] = 0.1 ether;

        vm.prank(address(vaultManager));

        operatorSlash.slashOperator(_exitTokenIds, _amounts);
        assertEq(0.1 ether, operatorSlash.nftHasCompensated(0));

        assertEq(operatorRegistry.operatorPledgeVaultBalances(1), 0.9 ether);

        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("operatorVaultAddr: ", operatorVaultAddr);
        console.log("operatorVaultImpl: ", address(vaultContract));
        vm.deal(address(operatorVaultAddr), 1 ether);

        vm.roll(200);

        uint256[] memory operatorIds = new uint256[] (1);
        operatorIds[0] = 1;
        vaultManager.settleAndReinvestElReward(operatorIds);
        vaultManager.claimRewardsOfUser(_exitTokenIds);
        assertEq(1 ether, address(24).balance); // 0.1 eth + 0.9 eth
    }

    function testUnstakeETH() public {
        vm.deal(address(20), 64 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 32 ether}(1);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(32 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, address(20).balance);

        vm.prank(address(20));
        liquidStaking.stakeETH{value: 32 ether}(1);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(64 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(64 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(0, address(20).balance);

        vm.prank(address(20));
        liquidStaking.unstakeETH(1, 32 ether);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(32 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, address(20).balance);

        vm.prank(address(20));
        liquidStaking.unstakeETH(1, 32 ether);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(0 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(64 ether, address(20).balance);
    }

    function testUnstakeETHOfLoan() public {
        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testELVault", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId);

        vm.deal(address(20), 32 ether);
        vm.prank(address(20));
        liquidStaking.stakeETH{value: 32 ether}(operatorId);
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(32 ether, neth.balanceOf(address(20)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(32 ether, liquidStaking.operatorPoolBalances(operatorId));
        assertEq(0 ether, address(20).balance);

        assertEq(32 ether, address(liquidStaking).balance);

        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

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
        vm.prank(address(_controllerAddress3));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(0 ether, address(liquidStaking).balance);

        assertEq(0 ether, liquidStaking.operatorPoolBalances(operatorId));

        vm.deal(address(21), 32 ether);
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 32 ether}(1);
        assertEq(0, vnft.balanceOf(address(21)));
        assertEq(32 ether, neth.balanceOf(address(21)));
        assertEq(1, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(0 ether, address(21).balance);
        assertEq(32 ether, address(liquidStaking).balance);

        assertEq(32 ether, address(liquidStaking).balance);

        assertEq(32 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(operatorId));

        vm.prank(address(20));
        liquidStaking.unstakeETH(operatorId, 2 ether);
        assertEq(30 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(operatorId));
        assertEq(0, vnft.balanceOf(address(20)));
        assertEq(30 ether, neth.balanceOf(address(20)));
        assertEq(1, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(32 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(2 ether, address(20).balance);
        assertEq(0 ether, liquidStaking.operatorPoolBalances(operatorId));
        assertEq(2 ether, liquidStaking.operatorLoanRecords(operatorId));
        assertEq(0 ether, liquidStaking.operatorLoanRecords(1));
        assertEq(30 ether, address(liquidStaking).balance);

        console.log("rate: 1", liquidStaking.getNethOut(1 ether));

        vm.deal(address(22), 2 ether);
        vm.prank(address(22));
        liquidStaking.stakeETH{value: 2 ether}(operatorId);
        assertEq(0, vnft.balanceOf(address(22)));
        assertEq(2 ether, neth.balanceOf(address(22)));
        assertEq(1, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(operatorId));
        assertEq(0 ether, address(22).balance);
        assertEq(0 ether, liquidStaking.operatorLoanRecords(operatorId));
        assertEq(0 ether, liquidStaking.operatorLoanRecords(1));
        assertEq(32 ether, address(liquidStaking).balance);
        assertEq(32 ether, liquidStaking.operatorPoolBalances(operatorId) + liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(operatorId));

        console.log("rate: 2", liquidStaking.getNethOut(1 ether));

        vm.prank(_dao);
        liquidStaking.setOperatorCanLoanAmounts(0 ether);

        assertEq(0 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(operatorId));

        vm.prank(_dao);
        liquidStaking.setOperatorCanLoanAmounts(32 ether);

        pubkey =
            bytes(hex"83d3693fb9da8aed60a5c94c51927158d6e3a4d36fa6982ba2c87f83260329baf08f93d000f9261911420a9c0f0eb022");
        sign = bytes(
            hex"b0e13147956deb0b188e79de8181d0f9f216a43cf8fe0435c5c919da0182400e440ff6ba11d1c2ec12bec824200d9d07130d53260e8f03d7292af14e909731435ffe5beb4e97f7e97e55cd555e99e23de6dbb5618a40bd26b7537b9cd4104370"
        );
        root = bytes32(hex"f497234b67c6258b9cd46627adb7a88a26a5b48cbe90ee3bdb24bf9c559a0595");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(0 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(operatorId));
        assertEq(0 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(1));

        vm.deal(address(23), 2 ether);
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 2 ether}(operatorId);

        assertEq(2 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(operatorId));
        assertEq(2 ether, liquidStaking.getOperatorNethUnstakePoolAmounts(1));
    }

    function testUnstakeNFT() public {
        vm.deal(address(21), 32 ether);
        vm.prank(address(21));
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        assertEq(1, vnft.balanceOf(address(21)));
        assertEq(0, neth.balanceOf(address(21)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0, neth.balanceOf(address(liquidStaking)));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(1));

        uint256[] memory tokenids = new uint256[] (1);
        tokenids[0] = 0;
        vm.prank(address(21));
        withdrawalRequest.unstakeNFT(tokenids);
        assertEq(0, vnft.balanceOf(address(21)));
        assertEq(0, neth.balanceOf(address(21)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0, neth.balanceOf(address(liquidStaking)));
        assertEq(0, liquidStaking.operatorNftPoolBalances(1));
        assertEq(32 ether, address(21).balance);
    }

    function testUnstakeNFT2() public {
        vm.roll(100);
        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 opId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testELVault", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(opId);

        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(opId, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(opId));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(opId));

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);
        bytes memory pubkey =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        bytes memory sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        bytes32 root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(0 ether, liquidStaking.operatorPoolBalances(opId));
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress3));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorNftPoolBalances(opId));

        uint256[] memory tokenids = new uint256[] (1);
        tokenids[0] = 0;
        vm.prank(address(74));
        withdrawalRequest.unstakeNFT(tokenids);

        assertEq(100, withdrawalRequest.getNftUnstakeBlockNumber(0));
        assertEq(0, withdrawalRequest.getUserUnstakeButOperatorNoExitNfs(opId)[0]);
        assertEq(1, vnft.balanceOf(address(74)));

        vm.roll(200);

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 2, clReward: 0.1 ether, clCapital: 0 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (1);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 200, slashAmount: 0});
        uint256[] memory empty = new uint256[] (0);

        assertEq(1, vnft.getActiveNftCountsOfOperator(2));
        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(opId);
        vm.deal(address(operatorVaultAddr), 1 ether);
        uint256[] memory operatorIds = new uint256[] (1);
        operatorIds[0] = opId;
        vaultManager.settleAndReinvestElReward(operatorIds);

        vm.deal(address(consensusVaultContract), 0.1 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 0.1 ether, 0);

        assertEq(1, vnft.balanceOf(address(74)));

        uint256[] memory tokenIds = new uint256[] (1);
        tokenIds[0] = 0;
        assertEq(200, vnft.getNftExitBlockNumbers(tokenIds)[0]);

        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(0.9 ether, address(74).balance);
        assertEq(0, vnft.balanceOf(address(74)));
    }

    function testResetOperatorVaultContract() public {
        ELVault vaultContract2 = new ELVault();
        ELVaultFactory vaultFactoryContract2 = new ELVaultFactory();
        vaultFactoryContract2.initialize(address(vaultContract2), address(liquidStaking), _dao);
        vaultFactoryContract2.setNodeOperatorRegistry(address(operatorRegistry));

        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 opId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testELVault", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(opId);
        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(opId);
        console.log("========testResetOperatorVaultContract==========", operatorVaultAddr);
        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(vaultFactoryContract2), address(0), 0, 0, 0
        );
        uint256[] memory resetOperatorIds = new uint256[] (1);
        resetOperatorIds[0] = opId;
        vm.prank(_dao);
        operatorRegistry.resetOperatorVaultContract(resetOperatorIds);
        operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(opId);
        console.log("========testResetOperatorVaultContract==========", operatorVaultAddr);
    }

    function testGetNextValidatorWithdrawalCredential() public {
        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(1));

        bytes memory w;
        w = vnft.getNextValidatorWithdrawalCredential(1);
        console.logBytes(w);

        bytes[] memory w2;
        w2 = vnft.getMultipleValidatorWithdrawalCredentials(1, 3);
        console.log("getMultipleValidatorWithdrawalCredentials");
        console.logBytes(w2[0]);
        console.logBytes(w2[1]);
        w2 = vnft.getMultipleValidatorWithdrawalCredentials(1, 4);
        assertEq(4, w2.length);
        w2 = vnft.getMultipleValidatorWithdrawalCredentials(1, 5);
        assertEq(5, w2.length);

        vm.deal(address(75), 32 ether);
        vm.prank(address(75));
        vm.deal(0x00dFaaE92ed72A05bC61262aA164f38B5626e106, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0x00dFaaE92ed72A05bC61262aA164f38B5626e106);
        assertEq(1, vnft.balanceOf(address(75)));
        assertEq(0, neth.balanceOf(address(75)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(64 ether, liquidStaking.operatorNftPoolBalances(1));

        w2 = vnft.getMultipleValidatorWithdrawalCredentials(1, 3);
        console.logBytes(w2[0]);
        console.logBytes(w2[1]);
        console.logBytes(w2[2]);
        w2 = vnft.getMultipleValidatorWithdrawalCredentials(1, 4);
        assertEq(4, w2.length);
        w2 = vnft.getMultipleValidatorWithdrawalCredentials(1, 5);
        console.logBytes(w2[0]);
        console.logBytes(w2[1]);
        console.logBytes(w2[2]);
        console.logBytes(w2[3]);
        console.logBytes(w2[4]);
        assertEq(5, w2.length);
    }

    function _stakePoolValidator() internal {
        vm.deal(address(75), 64 ether);
        vm.prank(address(75));
        liquidStaking.stakeETH{value: 64 ether}(1);
        assertEq(0, vnft.balanceOf(address(75)));
        assertEq(64 ether, neth.balanceOf(address(75)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(64 ether, liquidStaking.operatorPoolBalances(1));

        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        bytes memory pubkey =
            bytes(hex"a369806d61ade95f1f0395473e5c5bd633bde38d6abba3a9b1c2fe2049a27a4008cfd9643a4b8162853e37f41c957c6b");
        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        pubkey =
            bytes(hex"804424fd3989527628d71618cc0964f1934a778af35fae602b775f92a326863677f705f9b4fd264dbc66b328d7b09721");
        sign = bytes(
            hex"b0e13147956deb0b188e79de8181d0f9f216a43cf8fe0435c5c919da0182400e440ff6ba11d1c2ec12bec824200d9d07130d53260e8f03d7292af14e909731435ffe5beb4e97f7e97e55cd555e99e23de6dbb5618a40bd26b7537b9cd4104370"
        );
        root = bytes32(hex"f497234b67c6258b9cd46627adb7a88a26a5b48cbe90ee3bdb24bf9c559a0595");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
    }

    function testRequestLargeWithdrawals() public {
        _stakePoolValidator();

        vm.prank(address(75));
        uint256[] memory amounts = new uint256[] (1);
        amounts[0] = 40 ether;
        withdrawalRequest.requestLargeWithdrawals(1, amounts);
        assertEq(24 ether, neth.balanceOf(address(75)));
        assertEq(2, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(1, withdrawalRequest.getWithdrawalRequestIdOfOwner(address(75)).length);

        uint256 operatorId;
        uint256 withdrawHeight;
        uint256 withdrawNethAmount;
        uint256 withdrawExchange;
        uint256 claimEthAmount;
        address owner;
        bool isClaim;
        (operatorId, withdrawHeight, withdrawNethAmount, withdrawExchange, claimEthAmount, owner, isClaim) =
            withdrawalRequest.getWithdrawalOfRequestId(0);
        assertEq(operatorId, 1);
        assertEq(withdrawHeight, 1);
        assertEq(withdrawNethAmount, 40 ether);
        assertEq(withdrawExchange, 1 ether);
        assertEq(claimEthAmount, 40 ether);
        assertEq(owner, address(75));
        assertEq(isClaim, false);

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 64 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (2);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 200, slashAmount: 0});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 200, slashAmount: 0});
        uint256[] memory empty = new uint256[] (0);

        vm.roll(210);

        assertEq(2, vnft.getActiveNftCountsOfOperator(1));
        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        vm.deal(address(operatorVaultAddr), 1 ether);
        uint256[] memory operatorIds = new uint256[] (1);
        operatorIds[0] = 1;
        vaultManager.settleAndReinvestElReward(operatorIds);

        assertEq(0.9 ether, liquidStaking.operatorPoolBalances(1));

        vm.deal(address(consensusVaultContract), 64.1 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 64.1 ether, 0);

        assertEq(40 ether, address(withdrawalRequest).balance);
        assertEq(25 ether, address(liquidStaking).balance);
        assertEq(25 ether, liquidStaking.operatorPoolBalances(1));

        uint256[] memory requestIds = new uint256[] (1);
        requestIds[0] = 0;
        vm.prank(address(75));
        withdrawalRequest.claimLargeWithdrawals(requestIds);
        (,,,,,, isClaim) = withdrawalRequest.getWithdrawalOfRequestId(0);

        assertEq(isClaim, true);
        assertEq(40 ether, address(75).balance);
        assertEq(0 ether, address(withdrawalRequest).balance);
        assertEq(24 ether, liquidStaking.getUnstakeQuota(address(75))[0].quota);
    }

    function testValidatorSlash() public {
        _stakePoolValidator();
        assertEq(2, vnft.getActiveNftCountsOfOperator(1));

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 63.5 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (2);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 200, slashAmount: 0.5 ether});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 200, slashAmount: 0});
        uint256[] memory empty = new uint256[] (0);

        vm.roll(210);

        vm.deal(address(consensusVaultContract), 63.6 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 63.6 ether, 0);

        assertEq(64 ether, liquidStaking.getUnstakeQuota(address(75))[0].quota);
        assertEq(64.1 ether, liquidStaking.operatorPoolBalances(1));
    }

    function testValidatorSlash2() public {
        _stakePoolValidator();
        assertEq(2, vnft.getActiveNftCountsOfOperator(1));

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 61.5 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (2);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 200, slashAmount: 1.5 ether});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 200, slashAmount: 1 ether});
        uint256[] memory empty = new uint256[] (0);

        vm.roll(210);

        vm.deal(address(consensusVaultContract), 61.6 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 61.6 ether, 0);

        assertEq(0, vnft.balanceOf(address(liquidStaking)));

        assertEq(64 ether, liquidStaking.getUnstakeQuota(address(75))[0].quota);
        assertEq(62.6 ether, liquidStaking.operatorPoolBalances(1));

        uint256 balance;
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(0, balance);

        operatorRegistry.deposit{value: 1 ether}(1);
        assertEq(63.6 ether, liquidStaking.operatorPoolBalances(1));
        operatorRegistry.deposit{value: 1 ether}(1);
        assertEq(64.1 ether, liquidStaking.operatorPoolBalances(1));
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(0.5 ether, balance);
        operatorRegistry.deposit{value: 1 ether}(1);
        assertEq(64.1 ether, liquidStaking.operatorPoolBalances(1));
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(1.5 ether, balance);
    }

    function _stakeUserValidator() internal {
        vm.roll(100);
        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(1, vnft.getEmptyNftCounts());
        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);
        bytes memory pubkey =
            bytes(hex"a646616d3f394e9addff2d5e6744cf7923347ce5fc8358148875647fe227abe154331a3b3a6312f6f2ef39dd746c7ca8");
        bytes memory sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        bytes32 root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(0, vnft.getEmptyNftCounts());

        assertEq(vnft.validatorsOfOperator(1).length, 1);

        vm.deal(address(24), 32 ether);
        vm.prank(address(24));
        vm.deal(0x00dFaaE92ed72A05bC61262aA164f38B5626e106, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0x00dFaaE92ed72A05bC61262aA164f38B5626e106);
        assertEq(1, vnft.balanceOf(address(24)));
        assertEq(0, neth.balanceOf(address(24)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(1, vnft.getEmptyNftCounts());

        pubkey =
            bytes(hex"b5c28a10ac150d59c7ae852dfdb9155884fae9696bb20aae32195f996b1f2e5720736849da5fd5e92b815648fdae4b61");
        sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(vnft.validatorsOfOperator(1).length, 2);

        assertEq(0, vnft.getEmptyNftCounts());
        assertEq(2, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(2, vnft.getActiveNftCountsOfOperator(1));
    }

    function testValidatorSlash3() public {
        _stakeUserValidator();

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 0 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (1);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 200, slashAmount: 0.5 ether});
        uint256[] memory empty = new uint256[] (0);

        vm.roll(210);

        vm.deal(address(consensusVaultContract), 0.1 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 0.1 ether, 0);
        assertEq(0 ether, address(74).balance);
        assertEq(0.5 ether, address(operatorSlash).balance);
        uint256[] memory tokenIds = new uint256[] (1);
        tokenIds[0] = 0;
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(0.5 ether, address(74).balance);
        assertEq(0, operatorSlash.nftWillCompensated(0));
        assertEq(0, operatorSlash.nftHasCompensated(0));
        assertEq(0, operatorSlash.operatorCompensatedIndex());
    }

    function testValidatorSlash4() public {
        _stakeUserValidator();

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 0 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (1);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 200, slashAmount: 2 ether});
        uint256[] memory empty = new uint256[] (0);

        vm.roll(210);

        vm.deal(address(consensusVaultContract), 0.1 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 0.1 ether, 0);
        assertEq(0 ether, address(74).balance);
        assertEq(1 ether, address(operatorSlash).balance);
        uint256[] memory tokenIds = new uint256[] (1);
        tokenIds[0] = 0;
        assertEq(1 ether, operatorSlash.nftHasCompensated(0));
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(1 ether, address(74).balance);
        assertEq(1 ether, operatorSlash.nftWillCompensated(0));
        assertEq(0, operatorSlash.nftHasCompensated(0));
        assertEq(0, operatorSlash.operatorCompensatedIndex());

        operatorRegistry.deposit{value: 2 ether}(1);
        assertEq(1 ether, operatorSlash.nftHasCompensated(0));
        assertEq(0 ether, operatorSlash.nftWillCompensated(0));
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(2 ether, address(74).balance);
        assertEq(0, operatorSlash.nftHasCompensated(0));
        assertEq(1, operatorSlash.operatorCompensatedIndex());

        uint256 balance;
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(1 ether, balance);
    }

    function testValidatorSlash5() public {
        _stakeUserValidator();

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 0 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (2);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 200, slashAmount: 2 ether});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 200, slashAmount: 2 ether});

        vm.roll(210);

        vm.deal(address(consensusVaultContract), 0.1 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 0.1 ether, 0);
        assertEq(0 ether, address(74).balance);
        assertEq(1 ether, address(operatorSlash).balance);
        uint256[] memory tokenIds = new uint256[] (1);
        tokenIds[0] = 0;
        assertEq(1 ether, operatorSlash.nftHasCompensated(0));
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(1 ether, address(74).balance);
        assertEq(1 ether, operatorSlash.nftWillCompensated(0));
        assertEq(0, operatorSlash.nftHasCompensated(0));
        assertEq(0, operatorSlash.operatorCompensatedIndex());

        operatorRegistry.deposit{value: 2 ether}(1);
        assertEq(1 ether, operatorSlash.nftHasCompensated(0));
        assertEq(0 ether, operatorSlash.nftWillCompensated(0));
        assertEq(1 ether, operatorSlash.nftWillCompensated(1));
        assertEq(1 ether, operatorSlash.nftHasCompensated(1));
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(2 ether, address(74).balance);
        assertEq(0, operatorSlash.nftHasCompensated(0));
        assertEq(1, operatorSlash.operatorCompensatedIndex());

        uint256 balance;
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(0 ether, balance);

        operatorRegistry.deposit{value: 3 ether}(1);
        assertEq(0 ether, operatorSlash.nftHasCompensated(0));
        assertEq(0 ether, operatorSlash.nftWillCompensated(0));
        assertEq(0 ether, operatorSlash.nftWillCompensated(1));
        assertEq(2 ether, operatorSlash.nftHasCompensated(1));
        assertEq(2, operatorSlash.operatorCompensatedIndex());
        tokenIds[0] = 1;
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(2 ether, address(24).balance);
        assertEq(0, operatorSlash.nftHasCompensated(1));
        assertEq(2, operatorSlash.operatorCompensatedIndex());
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(2 ether, balance);
    }

    function testValidatorSlash6() public {
        _stakeUserValidator();

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 0 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (2);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 7300, slashAmount: 0 ether});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 7300, slashAmount: 0 ether});

        vm.roll(200);
        vm.prank(address(74));
        uint256[] memory tokenids = new uint256[] (1);
        tokenids[0] = 0;
        withdrawalRequest.unstakeNFT(tokenids);
        tokenids[0] = 1;
        vm.prank(address(24));
        withdrawalRequest.unstakeNFT(tokenids);
        assertEq(200, withdrawalRequest.getNftUnstakeBlockNumber(0));
        assertEq(200, withdrawalRequest.getNftUnstakeBlockNumber(1));
        assertEq(0, withdrawalRequest.getUserUnstakeButOperatorNoExitNfs(1)[0]);
        assertEq(1, withdrawalRequest.getUserUnstakeButOperatorNoExitNfs(1)[1]);
        assertEq(2, withdrawalRequest.getUserUnstakeButOperatorNoExitNfs(1).length);

        vm.deal(address(consensusVaultContract), 0.1 ether);

        assertEq(0, liquidStaking.operatorPoolBalances(1));

        vm.prank(address(withdrawOracle));

        vm.roll(7400);
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 0.1 ether, 0);
        assertEq(0 ether, address(74).balance);
        assertEq(0, address(operatorSlash).balance);
        assertEq(0.1 ether, liquidStaking.operatorPoolBalances(1));
    }

    function testValidatorSlash7() public {
        _stakePoolValidator();

        vm.deal(address(76), 32 ether);
        vm.prank(address(76));
        liquidStaking.stakeETH{value: 32 ether}(1);

        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        bytes memory pubkey =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        bytes memory sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        bytes32 root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");

        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(0, liquidStaking.operatorPoolBalances(1));

        vm.roll(200);

        vm.prank(address(75));
        uint256[] memory amounts = new uint256[] (1);
        amounts[0] = 40 ether;
        withdrawalRequest.requestLargeWithdrawals(1, amounts);
        assertEq(24 ether, neth.balanceOf(address(75)));
        assertEq(3, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(1, withdrawalRequest.getWithdrawalRequestIdOfOwner(address(75)).length);

        vm.prank(address(76));
        amounts[0] = 32 ether;
        withdrawalRequest.requestLargeWithdrawals(1, amounts);
        assertEq(0 ether, neth.balanceOf(address(76)));
        assertEq(3, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(1, withdrawalRequest.getWithdrawalRequestIdOfOwner(address(76)).length);

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 96 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (3);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 7300, slashAmount: 0 ether});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 7300, slashAmount: 0 ether});
        _exitValidatorInfo[2] = ExitValidatorInfo({exitTokenId: 2, exitBlockNumber: 7300, slashAmount: 0 ether});

        vm.deal(address(consensusVaultContract), 96.1 ether);

        vm.prank(address(withdrawOracle));

        vm.roll(7400);
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 96.1 ether, 0);

        assertEq(0 ether, address(75).balance);
        assertEq(0 ether, address(76).balance);
        assertEq(0, address(operatorSlash).balance);
        assertEq(72 ether, address(withdrawalRequest).balance);
        assertEq(24.1 ether, liquidStaking.operatorPoolBalances(1));

        uint256[] memory requestIds = new uint256[] (1);
        requestIds[0] = 0;
        vm.prank(address(75));
        withdrawalRequest.claimLargeWithdrawals(requestIds);

        requestIds[0] = 1;
        vm.prank(address(76));
        withdrawalRequest.claimLargeWithdrawals(requestIds);
        assertEq(40 ether, address(75).balance);
        assertEq(32 ether, address(76).balance);
        assertEq(0 ether, address(withdrawalRequest).balance);
        uint256 balance;
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(1 ether, balance);
    }

    function testValidatorSlash8() public {
        _stakePoolValidator();

        vm.deal(address(76), 32 ether);
        vm.prank(address(76));
        liquidStaking.stakeETH{value: 32 ether}(1);

        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        bytes memory pubkey =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        bytes memory sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        bytes32 root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");

        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);

        assertEq(0, liquidStaking.operatorPoolBalances(1));

        vm.roll(200);

        vm.prank(address(75));
        uint256[] memory amounts = new uint256[] (1);
        amounts[0] = 40 ether;
        withdrawalRequest.requestLargeWithdrawals(1, amounts);
        assertEq(24 ether, neth.balanceOf(address(75)));
        assertEq(3, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(1, withdrawalRequest.getWithdrawalRequestIdOfOwner(address(75)).length);

        vm.prank(address(76));
        amounts[0] = 32 ether;
        withdrawalRequest.requestLargeWithdrawals(1, amounts);
        assertEq(0 ether, neth.balanceOf(address(76)));
        assertEq(3, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(1, withdrawalRequest.getWithdrawalRequestIdOfOwner(address(76)).length);

        assertEq(2, withdrawalRequest.getWithdrawalOfOperator(1).length);
        uint256 pendingEthAmount;
        uint256 poolEthAmount;
        (pendingEthAmount, poolEthAmount) = withdrawalRequest.getOperatorLargeWithdrawalPendingInfo(1);
        assertEq(pendingEthAmount, 72 ether);
        assertEq(poolEthAmount, 0 ether);
        assertEq(withdrawalRequest.getTotalPendingClaimedAmounts(), 72 ether);

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 96 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (3);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 7300, slashAmount: 0 ether});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 7300, slashAmount: 0 ether});
        _exitValidatorInfo[2] = ExitValidatorInfo({exitTokenId: 2, exitBlockNumber: 7300, slashAmount: 0 ether});
        uint256[] memory empty = new uint256[] (0);
        uint256[] memory _largeExitDelayedRequestIds = new uint256[] (2);
        _largeExitDelayedRequestIds[0] = 0;
        _largeExitDelayedRequestIds[1] = 1;

        vm.deal(address(consensusVaultContract), 96.1 ether);

        vm.prank(address(withdrawOracle));
        vm.roll(7400);
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, 96.1 ether, 0);
        assertEq(withdrawalRequest.getTotalPendingClaimedAmounts(), 0 ether);

        assertEq(0 ether, address(75).balance);
        assertEq(0 ether, address(76).balance);
        assertEq(0, address(operatorSlash).balance);
        assertEq(72 ether, address(withdrawalRequest).balance);
        assertEq(24.1 ether, liquidStaking.operatorPoolBalances(1));

        uint256[] memory requestIds = new uint256[] (1);
        requestIds[0] = 0;
        vm.prank(address(75));
        withdrawalRequest.claimLargeWithdrawals(requestIds);

        requestIds[0] = 1;
        vm.prank(address(76));
        withdrawalRequest.claimLargeWithdrawals(requestIds);
        assertEq(40 ether, address(75).balance);
        assertEq(32 ether, address(76).balance);
        assertEq(0 ether, address(withdrawalRequest).balance);

        WithdrawInfo[] memory _withdrawInfo2 = new WithdrawInfo[] (0);
        ExitValidatorInfo[] memory _exitValidatorInfo2 = new ExitValidatorInfo[] (0);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo2, _exitValidatorInfo2, 0 ether, 0);
        assertEq(24.1 ether, liquidStaking.operatorPoolBalances(1));
        uint256 balance;
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(1 ether, balance);
    }

    function testLiquidStaking() public {
        vm.prank(_dao);
        liquidStaking.setOperatorCanLoanAmounts(100 ether);
        assertEq(liquidStaking.operatorCanLoanAmounts(), 100 ether);

        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(500);
        assertEq(liquidStaking.depositFeeRate(), 500);

        liquidStaking.setDaoAddress(address(1000));
        assertEq(address(liquidStaking.dao()), address(1000));
        _dao = address(1000);

        vm.prank(_dao);
        liquidStaking.changeCountractSetting(
            address(1000),
            address(1000),
            address(1000),
            address(1000),
            address(1000),
            address(1000),
            address(stakingManager)
        );

        assertEq(address(liquidStaking.nodeOperatorRegistryContract()), address(1000));

        assertEq(address(liquidStaking.withdrawOracleContract()), address(1000));

        assertEq(address(liquidStaking.operatorSlashContract()), address(1000));

        assertEq(address(liquidStaking.withdrawalRequestContract()), address(1000));

        assertEq(address(liquidStaking.vaultManagerContractAddress()), address(1000));

        assertEq(address(liquidStaking.daoVaultAddress()), address(1000));
    }

    function testOperatorSlash() public {
        vm.prank(_dao);
        operatorSlash.setOperatorSlashSetting(address(1000), address(0), address(0), address(0), address(0));
        assertEq(address(operatorSlash.nodeOperatorRegistryContract()), address(1000));

        vm.prank(_dao);
        operatorSlash.setOperatorSlashSetting(address(0), address(1000), address(0), address(0), address(0));
        assertEq(address(operatorSlash.withdrawalRequestContract()), address(1000));

        vm.prank(_dao);
        operatorSlash.setOperatorSlashSetting(address(0), address(0), address(1000), address(0), address(0));
        assertEq(address(operatorSlash.vaultManagerContractAddress()), address(1000));

        vm.prank(_dao);
        operatorSlash.setOperatorSlashSetting(address(0), address(0), address(0), address(1000), address(0));
        assertEq(address(operatorSlash.liquidStakingContract()), address(1000));

        operatorSlash.setDaoAddress(address(1000));
        assertEq(address(operatorSlash.dao()), address(1000));
    }

    function testWithdrawalRequest() public {
        vm.prank(_dao);
        withdrawalRequest.setNodeOperatorRegistryContract(address(1000));
        assertEq(address(withdrawalRequest.nodeOperatorRegistryContract()), address(1000));

        vm.prank(_dao);
        withdrawalRequest.setVaultManagerContract(address(1000));
        assertEq(address(withdrawalRequest.vaultManagerContract()), address(1000));

        vm.prank(_dao);
        withdrawalRequest.setLiquidStaking(address(1000));
        assertEq(address(withdrawalRequest.liquidStakingContract()), address(1000));

        withdrawalRequest.setDaoAddress(address(1000));
        assertEq(address(withdrawalRequest.dao()), address(1000));
    }

    function testVaultManager2() public {
        vm.prank(_dao);
        vaultManager.setVaultManagerSetting(0, 0, address(0), address(0), address(0), address(1000));
        assertEq(address(vaultManager.nodeOperatorRegistryContract()), address(1000));

        vm.prank(_dao);
        vaultManager.setVaultManagerSetting(0, 0, address(0), address(0), address(1000), address(0));
        assertEq(address(vaultManager.withdrawOracleContractAddress()), address(1000));

        vm.prank(_dao);
        vaultManager.setVaultManagerSetting(0, 0, address(0), address(1000), address(0), address(0));
        assertEq(address(vaultManager.operatorSlashContract()), address(1000));

        vaultManager.setDaoAddress(address(1000));
        assertEq(address(vaultManager.dao()), address(1000));

        vm.prank(address(1000));
        vaultManager.setVaultManagerSetting(1000, 0, address(0), address(0), address(0), address(0));
        assertEq(vaultManager.daoElCommissionRate(), 1000);

        vm.prank(address(1000));
        vaultManager.setVaultManagerSetting(0, 0, address(1000), address(0), address(0), address(0));
        assertEq(address(vaultManager.liquidStakingContract()), address(1000));
    }

    function testNodeOperatorRegistry2() public {
        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(1000), address(0), address(0), address(0), address(0), address(0), 0, 0, 0
        );
        assertEq(address(operatorRegistry.dao()), address(1000));

        _dao = address(1000);

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(1000), address(0), address(0), address(0), 0, 0, 0
        );
        assertEq(address(operatorRegistry.liquidStakingContract()), address(1000));

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(0), address(0), 0, 0, 1000
        );
        assertEq(operatorRegistry.permissionlessBlockNumber(), 1000);

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(1000), address(0), address(0), 0, 0, 0
        );
        assertEq(address(operatorRegistry.operatorSlashContract()), address(1000));

        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 opId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testELVault", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(0), address(0), 0, 1000, 0
        );
        assertEq(operatorRegistry.registrationFee(), 1000);

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(1000), address(0), address(0), address(0), address(0), 0, 0, 0
        );
        assertEq(address(operatorRegistry.daoVaultAddress()), address(1000));

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorRegistrySetting(
            address(0), address(0), address(0), address(0), address(1000), address(0), 0, 0, 0
        );
        assertEq(address(operatorRegistry.vaultFactoryContract()), address(1000));

        vm.prank(_dao);
        operatorRegistry.setOperatorCommissionRate(1, 2500);
        uint256[] memory _operatorIds = new uint256[] (2);
        _operatorIds[0] = 1;
        _operatorIds[1] = opId;
        uint256[] memory rates = operatorRegistry.getOperatorCommissionRate(_operatorIds);
        assertEq(rates[0], 2500);
        assertEq(rates[1], 700);
        assertEq(rates.length, 2);
    }

    function testVnft() public {
        _stakePoolValidator();

        vm.roll(100);
        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(2, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(1, vnft.getEmptyNftCounts());

        assertEq(1, vnft.getEmptyNftCountsOfOperator(1));

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);
        bytes memory pubkey =
            bytes(hex"a646616d3f394e9addff2d5e6744cf7923347ce5fc8358148875647fe227abe154331a3b3a6312f6f2ef39dd746c7ca8");
        bytes memory sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        bytes32 root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(2, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(0, vnft.getEmptyNftCounts());
        assertEq(0, vnft.getEmptyNftCountsOfOperator(1));

        assertEq(vnft.validatorsOfOperator(1).length, 3);

        vm.deal(address(24), 32 ether);
        vm.prank(address(24));
        vm.deal(0x00dFaaE92ed72A05bC61262aA164f38B5626e106, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0x00dFaaE92ed72A05bC61262aA164f38B5626e106);
        assertEq(1, vnft.balanceOf(address(24)));
        assertEq(0, neth.balanceOf(address(24)));
        assertEq(2, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, neth.balanceOf(address(liquidStaking)));
        assertEq(1, vnft.getEmptyNftCounts());
        assertEq(1, vnft.getEmptyNftCountsOfOperator(1));

        pubkey =
            bytes(hex"b5c28a10ac150d59c7ae852dfdb9155884fae9696bb20aae32195f996b1f2e5720736849da5fd5e92b815648fdae4b61");
        sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(vnft.validatorsOfOperator(1).length, 4);
        assertEq(0, vnft.getEmptyNftCountsOfOperator(1));

        assertEq(0, vnft.getEmptyNftCounts());
        assertEq(2, vnft.getUserActiveNftCountsOfOperator(1));
        assertEq(4, vnft.getActiveNftCountsOfOperator(1));

        assertEq(2, vnft.activeValidatorOfUser().length);
        assertEq(2, vnft.activeValidatorsOfStakingPool().length);

        assertEq(2, vnft.activeNftsOfUser().length);
        assertEq(2, vnft.activeNftsOfStakingPool().length);
        assertEq(0, vnft.activeNftsOfStakingPool()[0]);
        assertEq(1, vnft.activeNftsOfStakingPool()[1]);
        assertEq(2, vnft.activeNftsOfUser()[0]);
        assertEq(3, vnft.activeNftsOfUser()[1]);

        console.log("=======testVnft=====");
        console.logBytes(vnft.activeValidatorOfUser()[0]);
        console.logBytes(vnft.activeValidatorOfUser()[1]);
        console.logBytes(vnft.activeValidatorsOfStakingPool()[0]);
        console.logBytes(vnft.activeValidatorsOfStakingPool()[1]);

        assertEq(4, vnft.getTotalActiveNftCounts());
        console.logBytes(vnft.validatorOf(1));
        assertEq(1, vnft.operatorOf(1));

        vm.prank(address(liquidStaking));
        vnft.whiteListBurn(3);
        assertEq(vnft.validatorsOfOperator(1).length, 3);

        vnft.setLiquidStaking(address(1000));
        assertEq(address(vnft.liquidStakingContractAddress()), address(1000));
    }

    function testNftGetActiveNftCountsOfOperator() public {
        vm.roll(100);
        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(1, vnft.getEmptyNftCounts());

        assertEq(0, vnft.getActiveNftCountsOfOperator(1));

        uint256[] memory tokenids = new uint256[] (1);
        tokenids[0] = 0;
        vm.prank(address(74));
        withdrawalRequest.unstakeNFT(tokenids);

        assertEq(0, vnft.balanceOf(address(74)));
        assertEq(32 ether, address(74).balance);

        assertEq(0, vnft.getActiveNftCountsOfOperator(1));
    }

    function testWithdrawalCredentials() public view {
        bytes memory withdrawalCredentials =
            bytes.concat(hex"010000000000000000000000", abi.encodePacked(consensusVaultContractAddr));
        console.log("========withdrawalCredentials========1");
        console.logBytes(withdrawalCredentials);

        console.log("========withdrawalCredentials========2");

        bytes memory result = abi.encodePacked(hex"010000000000000000000000", consensusVaultContractAddr);
        console.logBytes(result);

        bytes32 withdrawCredentials = abi.decode(result, (bytes32));
        console.log("========withdrawalCredentials========3");
        console.logBytes32(withdrawCredentials);
    }

    // LargeStaking
    function checkStakingInfo(
        uint256 _stakingId,
        bool _isELRewardSharing,
        uint256 _operatorId,
        uint256 _stakingAmount,
        uint256 _alreadyStakingAmount,
        uint256 _unstakeRequestAmount,
        uint256 _unstakeAmount
    ) public {
        (
            bool isELRewardSharing,
            ,
            uint256 operatorId,
            uint256 stakingAmount,
            uint256 alreadyStakingAmount,
            uint256 unstakeRequestAmount,
            uint256 unstakeAmount,
            ,
            ,
        ) = largeStaking.largeStakings(_stakingId);

        assertEq(_isELRewardSharing, isELRewardSharing);
        assertEq(_operatorId, operatorId);
        assertEq(_stakingAmount, stakingAmount);
        assertEq(_alreadyStakingAmount, alreadyStakingAmount);
        assertEq(_unstakeRequestAmount, unstakeRequestAmount);
        assertEq(_unstakeAmount, unstakeAmount);
    }

    function checkStakingInfoPermissions(uint256 _stakingId, address _owner, bytes32 _withdrawCredentials) public {
        (,,,,,,, address owner,, bytes32 withdrawCredentials) = largeStaking.largeStakings(_stakingId);

        assertEq(_owner, owner);
        assertEq(_withdrawCredentials, withdrawCredentials);
    }

    function checkSettleInfo(uint256 _stakingId, uint256 _sharePoint, uint256 _reward) public {
        (uint256 valuePerSharePoint, uint256 rewardBalance) = largeStaking.eLSharedRewardSettleInfo(_stakingId);
        assertEq(_sharePoint, valuePerSharePoint);
        assertEq(_reward, rewardBalance);
    }

    function testFailstartupSharedRewardPool() public {
        largeStaking.startupSharedRewardPool(1);
    }

    function teststartupSharedRewardPool2() public {
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);
    }

    function testFailstartupSharedRewardPool3() public {
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);
    }

    function testFailLargeStaking() public {
        vm.deal(address(1000), 3200 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
    }

    function testFailLargeStaking2() public {
        vm.deal(address(1000), 3200 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 321 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
    }

    function testLargeStaking() public {
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);

        // shared reward 0
        vm.deal(address(1000), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        (uint256 operatorId, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(1);
        console.log("operatorId", operatorId);
        console.log("rewardPoolAddr", rewardPoolAddr);
        console.log("rewards", rewards);

        checkStakingInfo(1, true, 1, 320 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            1, address(1000), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(1, 0, 0);
        assertEq(largeStaking.totalShares(1), 320 ether);

        // private 1
        vm.deal(address(1001), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);
        (uint256 operatorId2, address rewardPoolAddr2, uint256 rewards2) = largeStaking.getRewardPoolInfo(2);
        console.log("operatorId2", operatorId2);
        console.log("rewardPoolAddr2", rewardPoolAddr2);
        console.log("rewards2", rewards2);

        checkStakingInfo(2, false, 1, 960 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            2, address(1001), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(2, 0, 0);
        assertEq(largeStaking.totalShares(1), 320 ether);

        // shared reward 2
        vm.deal(address(1002), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1002));
        largeStaking.largeStake{value: 320 ether}(1, address(1002), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        (uint256 operatorId3, address rewardPoolAddr3, uint256 rewards3) = largeStaking.getRewardPoolInfo(3);
        console.log("operatorId3", operatorId3);
        console.log("rewardPoolAddr3", rewardPoolAddr3);
        console.log("rewards3", rewards3);
        assertEq(rewardPoolAddr, rewardPoolAddr3);

        checkStakingInfo(3, true, 1, 320 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            3, address(1002), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );

        checkSettleInfo(3, 0, 0);
        checkSettleInfo(3, 0, 0);
        assertEq(largeStaking.totalShares(1), 640 ether);

        vm.deal(rewardPoolAddr3, 10 ether);
        assertEq(largeStaking.valuePerShare(1), 0);

        // shared reward 3
        vm.deal(address(1003), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1003));
        largeStaking.largeStake{value: 320 ether}(1, address(1003), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        (uint256 operatorId4, address rewardPoolAddr4, uint256 rewards4) = largeStaking.getRewardPoolInfo(4);
        console.log("operatorId4", operatorId4);
        console.log("rewardPoolAddr4", rewardPoolAddr4);
        console.log("rewards4", rewards4);
        assertEq(rewardPoolAddr, rewardPoolAddr4);
        checkStakingInfo(4, true, 1, 320 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            4, address(1003), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        assertEq(largeStaking.totalShares(1), 960 ether);
        console.log("-------largeStaking.valuePerShare(1)---------", largeStaking.valuePerShare(1));

        // total reward 10 eth
        //      operator reward 0.7 eth; dao 0.3 eth
        //      sharded pool 9 eth
        uint256 _sharePoint = 9 ether * 1e18 / 640 ether;
        assertEq(largeStaking.valuePerShare(1), _sharePoint);
        assertEq(largeStaking.unclaimedSharedRewards(1), 10 ether);
        assertEq(largeStaking.operatorSharedRewards(1), 0.7 ether);
        assertEq(largeStaking.daoSharedRewards(1), 0.3 ether);

        assertEq(largeStaking.reward(1), 4.5 ether);
        assertEq(largeStaking.reward(3), 4.5 ether);
        assertEq(largeStaking.reward(2), 0 ether);
        assertEq(largeStaking.reward(4), 0 ether);
        checkSettleInfo(1, 0, 0);
        checkSettleInfo(2, 0, 0);
        checkSettleInfo(4, _sharePoint, 0);

        // claim reward
        vm.prank(address(1000));
        largeStaking.claimRewardsOfUser(1, 4.5 ether);
        assertEq(largeStaking.reward(1), 0 ether);
        assertEq(address(1000).balance, 4.5 ether);

        vm.prank(address(1002));
        largeStaking.claimRewardsOfUser(3, 4.5 ether);
        assertEq(largeStaking.reward(2), 0 ether);
        assertEq(address(1002).balance, 4.5 ether);

        checkSettleInfo(1, _sharePoint, 0);
        checkSettleInfo(3, _sharePoint, 0);
    }

    function testAppenLargeStake1() public {
        // private 1
        vm.deal(address(1001), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);
        (uint256 operatorId2, address rewardPoolAddr2, uint256 rewards2) = largeStaking.getRewardPoolInfo(1);
        console.log("operatorId2", operatorId2);
        console.log("rewardPoolAddr2", rewardPoolAddr2);
        console.log("rewards2", rewards2);

        checkStakingInfo(1, false, 1, 960 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            1, address(1001), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(1, 0, 0);
        assertEq(largeStaking.totalShares(1), 0 ether);

        vm.deal(address(1000001), 320 ether); // other account
        vm.prank(address(1000001));
        largeStaking.appendLargeStake{value: 320 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        checkStakingInfo(1, false, 1, 1280 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            1, address(1001), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(1, 0, 0);
        assertEq(largeStaking.totalShares(1), 0 ether);
    }

    function testAppenLargeStake2() public {
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);

        // shared reward 0
        vm.deal(address(1000), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        (uint256 operatorId, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(1);
        console.log("operatorId", operatorId);
        console.log("rewardPoolAddr", rewardPoolAddr);
        console.log("rewards", rewards);

        checkStakingInfo(1, true, 1, 320 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            1, address(1000), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(1, 0, 0);
        assertEq(largeStaking.totalShares(1), 320 ether);

        // append
        vm.deal(address(1000001), 320 ether); // other account
        vm.prank(address(1000001));
        largeStaking.appendLargeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        checkStakingInfo(1, true, 1, 640 ether, 0, 0, 0);
        checkSettleInfo(1, 0, 0);
        assertEq(largeStaking.totalShares(1), 640 ether);

        vm.deal(rewardPoolAddr, 10 ether);

        vm.deal(address(1000002), 320 ether);
        vm.prank(address(1000002));
        largeStaking.appendLargeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        checkStakingInfo(1, true, 1, 960 ether, 0, 0, 0);

        uint256 _sharePoint = 9 ether * 1e18 / 640 ether;
        checkSettleInfo(1, _sharePoint, 9 ether);
        assertEq(largeStaking.reward(1), 9 ether);
        assertEq(largeStaking.totalShares(1), 960 ether);
    }

    function testLargeUnstake() public {
        // private 1
        vm.deal(address(1001), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);
        (uint256 operatorId2, address rewardPoolAddr2, uint256 rewards2) = largeStaking.getRewardPoolInfo(1);
        console.log("operatorId2", operatorId2);
        console.log("rewardPoolAddr2", rewardPoolAddr2);
        console.log("rewards2", rewards2);

        vm.deal(rewardPoolAddr2, 10 ether);
        assertEq(largeStaking.reward(1), 9 ether);
        assertEq(largeStaking.daoPrivateRewards(1), 0 ether);
        assertEq(largeStaking.operatorPrivateRewards(1), 0 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 0 ether);
        largeStaking.settleElPrivateReward(1);
        assertEq(largeStaking.reward(1), 9 ether);
        assertEq(largeStaking.daoPrivateRewards(1), 0.3 ether);
        assertEq(largeStaking.operatorPrivateRewards(1), 0.7 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 10 ether);

        checkStakingInfo(1, false, 1, 960 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            1, address(1001), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(1, 0, 0);
        assertEq(largeStaking.totalShares(1), 0 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 30);
        vm.prank(address(1001));
        largeStaking.largeUnstake(1, 480 ether);
        assertEq(address(1001).balance, 480 ether);
        checkStakingInfo(1, false, 1, 960 ether, 480 ether, 480 ether, 480 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 15);

        vm.prank(address(1001));
        largeStaking.claimRewardsOfUser(1, 9 ether);
        assertEq(largeStaking.reward(1), 0 ether);
        assertEq(address(1001).balance, 489 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 1 ether);

        // shared reward
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);

        vm.deal(address(1000), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        (uint256 operatorId, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(2);
        console.log("operatorId", operatorId);
        console.log("rewardPoolAddr", rewardPoolAddr);
        console.log("rewards", rewards);
        assertEq(largeStaking.totalShares(1), 320 ether);
        checkStakingInfo(2, true, 1, 320 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            2, address(1000), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(2, 0, 0);
        assertEq(largeStaking.totalShares(1), 320 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 25);

        vm.deal(rewardPoolAddr, 10 ether);

        vm.prank(address(1000));
        largeStaking.largeUnstake(2, 160 ether);
        checkStakingInfo(2, true, 1, 320 ether, 160 ether, 160 ether, 160 ether);
        assertEq(largeStaking.totalShares(1), 160 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 20);

        uint256 _sharePoint = 9 ether * 1e18 / 320 ether;
        checkSettleInfo(2, _sharePoint, 9 ether);
        assertEq(largeStaking.reward(2), 9 ether);
        assertEq(largeStaking.daoSharedRewards(1), 0.3 ether);
        assertEq(largeStaking.operatorSharedRewards(1), 0.7 ether);
        assertEq(largeStaking.unclaimedSharedRewards(1), 10 ether);

        vm.prank(address(1000));
        largeStaking.claimRewardsOfUser(2, 9 ether);
        assertEq(largeStaking.reward(2), 0 ether);
        assertEq(largeStaking.unclaimedSharedRewards(1), 1 ether);
        assertEq(address(1000).balance, 169 ether);
    }

    function testFailMigrateStake() public {
        // RequireOperatorTrusted()
        bytes[] memory pubkeys = new bytes[] (1);
        pubkeys[0] =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        largeStaking.migrateStake(
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            false,
            pubkeys
        );
    }

    function testFailMigrateStake2() public {
        // InvalidWithdrawalCredentials()
        bytes[] memory pubkeys = new bytes[] (1);
        pubkeys[0] =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        vm.prank(_controllerAddress);
        largeStaking.migrateStake(
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            false,
            pubkeys
        );
    }

    function testFailMigrateStake3() public {
        // SharedRewardPoolNotOpened()
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);

        bytes[] memory pubkeys = new bytes[] (1);
        pubkeys[0] =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        vm.prank(_controllerAddress);
        largeStaking.migrateStake(
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            true,
            pubkeys
        );
    }

    function testMigrateStake() public {
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);
        bytes[] memory pubkeys = new bytes[] (2);
        pubkeys[0] =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        pubkeys[1] =
            bytes(hex"a646616d3f394e9addff2d5e6744cf7923347ce5fc8358148875647fe227abe154331a3b3a6312f6f2ef39dd746c7ca8");

        vm.prank(_controllerAddress);
        largeStaking.migrateStake(
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            true,
            pubkeys
        );
        checkStakingInfo(1, true, 1, 64 ether, 64 ether, 0, 0);
        checkStakingInfoPermissions(
            1,
            0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc,
            largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );

        vm.prank(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc);
        largeStaking.largeUnstake(1, 32 ether);
        checkStakingInfo(1, true, 1, 64 ether, 64 ether, 32 ether, 0 ether);

        pubkeys[0] =
            bytes(hex"8b428f69290c6689d594b90c9256e48cc89ae852c233825146013e65c1cc0555248b89b5a0dfd3e61613bc9b9ed306b8");
        pubkeys[1] =
            bytes(hex"972213419397cfd4c01c7325738d6ae7b3ffbd49a576623f4fd50215db51e56b5e1f31983dcc10eafdf4b5bd598db0ff");

        largeStaking.appendMigrateStake(
            1, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, pubkeys
        );
        checkStakingInfo(1, true, 1, 128 ether, 128 ether, 32 ether, 0 ether);
    }

    function testLargeStakingRegisterValidator() public {
        // private 1
        vm.deal(address(1001), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);
        (uint256 operatorId2, address rewardPoolAddr2, uint256 rewards2) = largeStaking.getRewardPoolInfo(1);
        console.log("operatorId2", operatorId2);
        console.log("rewardPoolAddr2", rewardPoolAddr2);
        console.log("rewards2", rewards2);

        vm.deal(rewardPoolAddr2, 10 ether);
        assertEq(largeStaking.reward(1), 9 ether);
        assertEq(largeStaking.daoPrivateRewards(1), 0 ether);
        assertEq(largeStaking.operatorPrivateRewards(1), 0 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 0 ether);
        largeStaking.settleElPrivateReward(1);
        assertEq(largeStaking.reward(1), 9 ether);
        assertEq(largeStaking.daoPrivateRewards(1), 0.3 ether);
        assertEq(largeStaking.operatorPrivateRewards(1), 0.7 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 10 ether);

        checkStakingInfo(1, false, 1, 960 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            1, address(1001), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(1, 0, 0);
        assertEq(largeStaking.totalShares(1), 0 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 30);
        vm.prank(address(1001));
        largeStaking.largeUnstake(1, 480 ether);
        assertEq(address(1001).balance, 480 ether);
        checkStakingInfo(1, false, 1, 960 ether, 480 ether, 480 ether, 480 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 15);

        vm.prank(address(1001));
        largeStaking.claimRewardsOfUser(1, 9 ether);
        assertEq(largeStaking.reward(1), 0 ether);
        assertEq(address(1001).balance, 489 ether);
        assertEq(largeStaking.unclaimedPrivateRewards(1), 1 ether);

        // shared reward
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);

        vm.deal(address(1000), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        (uint256 operatorId, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(2);
        console.log("operatorId", operatorId);
        console.log("rewardPoolAddr", rewardPoolAddr);
        console.log("rewards", rewards);
        assertEq(largeStaking.totalShares(1), 320 ether);
        checkStakingInfo(2, true, 1, 320 ether, 0, 0, 0);
        checkStakingInfoPermissions(
            2, address(1000), largeStaking.getWithdrawCredentials(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc)
        );
        checkSettleInfo(2, 0, 0);
        assertEq(largeStaking.totalShares(1), 320 ether);
        assertEq(largeStaking.getOperatorValidatorCounts(1), 25);

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
        checkStakingInfo(1, false, 1, 960 ether, 512 ether, 480 ether, 480 ether);

        pubkeys[0] =
            bytes(hex"93943bd530b79623af943a2af636f06c327203d82784fafda621439438c418bd8d26c82061bbc956fc7f0f8ddb138173");
        vm.prank(_controllerAddress);
        largeStaking.registerValidator(2, pubkeys, signatures, depositDataRoots);
        checkStakingInfo(2, true, 1, 320 ether, 32 ether, 0, 0);
    }

    function testFailDuplicatePubkey() public {
        vm.deal(address(1001), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);

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
        vm.prank(_controllerAddress);
        largeStaking.registerValidator(1, pubkeys, signatures, depositDataRoots);
    }

    function testFailReportCLStakingData() public {
        vm.deal(address(1001), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);
        checkStakingInfo(1, false, 1, 960 ether, 0, 0, 0);

        // shared reward
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);

        vm.deal(address(1000), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        checkStakingInfo(2, true, 1, 320 ether, 0, 0, 0);

        bytes[] memory pubkeys = new bytes[](5);
        bytes[] memory signatures = new bytes[](5);
        bytes32[] memory depositDataRoots = new bytes32[](5);

        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        signatures[0] = sign;
        depositDataRoots[0] = root;
        signatures[1] = sign;
        depositDataRoots[1] = root;
        signatures[2] = sign;
        depositDataRoots[2] = root;
        signatures[3] = sign;
        depositDataRoots[3] = root;
        signatures[4] = sign;
        depositDataRoots[4] = root;
        pubkeys[0] =
            bytes(hex"9200d672c314c389a88c1d7695d790ec73181cc60978c548c80c3c4787ee8da817e38904e3d0b6105679ba7f2e4f3d7a");
        pubkeys[1] =
            bytes(hex"9832164ad7eaeb6e649600d1ff7f25faf1ad7a829b6dc6133011bc38a5920761182a5b861345fb315d16dd0841eebc1a");
        pubkeys[2] =
            bytes(hex"a11d4b964034b0a9a825cd6de67e4f23749f81bc38594b21126ad606e59f1acc2eb64d058f7c9ac662e0f7288c9fbd5e");
        pubkeys[3] =
            bytes(hex"87ad33e8fffe7c62177d2c860228d5de2cd5041484bdbbe05241fa9ef72feb9dbc201010e4ce9e6d1807d08216b22d0a");
        pubkeys[4] =
            bytes(hex"8186b51b20e581a988482f2ab6b1d8084c151fd7eabdc161c5b6a5e512bd098d771c5d96c1ffaabed4a0d570227050fb");
        vm.prank(_controllerAddress);
        largeStaking.registerValidator(1, pubkeys, signatures, depositDataRoots);
        checkStakingInfo(1, false, 1, 960 ether, 160 ether, 0, 0);

        CLStakingExitInfo[] memory _clStakingExitInfo = new CLStakingExitInfo[] (1);
        CLStakingSlashInfo[] memory _clStakingSlashInfo = new CLStakingSlashInfo[] (1);
        bytes[] memory ps = new bytes[](2);
        ps[0] = pubkeys[0];
        ps[1] = pubkeys[1];
        _clStakingExitInfo[0] = CLStakingExitInfo({stakingId: 1, pubkeys: ps});
        _clStakingSlashInfo[0] = CLStakingSlashInfo({stakingId: 1, slashAmount: 1 ether, pubkey: pubkeys[0]});

        vm.prank(address(withdrawOracle));
        largeStaking.reportCLStakingData(_clStakingExitInfo, _clStakingSlashInfo);
        checkStakingInfo(1, false, 1, 960 ether, 160 ether, 64 ether, 64 ether);

        pubkeys[0] =
            bytes(hex"a51358e07d52a08bc4fdc6b0e17e5a5d543955cddbf5ad1c371006a706d83db86ba9c1f4f37d07c2455ed8ec1956cd07");
        pubkeys[1] =
            bytes(hex"af9de2b0d1700e3a3757293c4162e59b793e455d6ffdf1db956dc431ae4fedaed1ce6b94bf403c2f274d188ad99f0ec8");
        pubkeys[2] =
            bytes(hex"81b1688beb9bf70dd4a6ee13bb687444344e8345bbfc6a8a81d2562ab429673c8306581a6482934650cff5866004cea5");
        pubkeys[3] =
            bytes(hex"b727b205d752f10cfbc515ac68646ed27b984bc70f278e46054a750f597b9d6d93c51987bac8cf0c9c11decb3be652a0");
        pubkeys[4] =
            bytes(hex"8def5a22758d73598ae964fa71be5fb6c4cc2e1f098e10cb2f0fef2d498a8acfd9554c9b6f9b20d2a2fe613ccea94656");
        vm.prank(_controllerAddress);
        largeStaking.registerValidator(2, pubkeys, signatures, depositDataRoots);

        checkStakingInfo(2, true, 1, 320 ether, 160 ether, 0, 0);
        ps[0] = pubkeys[0];
        ps[1] = pubkeys[1];
        _clStakingExitInfo[0] = CLStakingExitInfo({stakingId: 1, pubkeys: ps});
        _clStakingSlashInfo[0] = CLStakingSlashInfo({stakingId: 1, slashAmount: 1 ether, pubkey: pubkeys[0]});

        // InvalidReport(); -> validatorOfStaking[sInfo.pubkey] != sInfo.stakingId
        vm.prank(address(withdrawOracle));
        largeStaking.reportCLStakingData(_clStakingExitInfo, _clStakingSlashInfo);
    }

    function testReportCLStakingData() public {
        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 operatorId = operatorRegistry.registerOperator{value: 1.1 ether}(
            "testELVault", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId);

        vm.deal(address(1001), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 960 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);
        checkStakingInfo(1, false, 1, 960 ether, 0, 0, 0);

        // shared reward
        vm.prank(_owner);
        largeStaking.startupSharedRewardPool(1);

        vm.prank(_owner3);
        largeStaking.startupSharedRewardPool(2);

        vm.deal(address(1000), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 320 ether}(
            operatorId, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true
        );
        checkStakingInfo(2, true, operatorId, 320 ether, 0, 0, 0);

        bytes[] memory pubkeys = new bytes[](5);
        bytes[] memory signatures = new bytes[](5);
        bytes32[] memory depositDataRoots = new bytes32[](5);

        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        signatures[0] = sign;
        depositDataRoots[0] = root;
        signatures[1] = sign;
        depositDataRoots[1] = root;
        signatures[2] = sign;
        depositDataRoots[2] = root;
        signatures[3] = sign;
        depositDataRoots[3] = root;
        signatures[4] = sign;
        depositDataRoots[4] = root;
        pubkeys[0] =
            bytes(hex"9200d672c314c389a88c1d7695d790ec73181cc60978c548c80c3c4787ee8da817e38904e3d0b6105679ba7f2e4f3d7a");
        pubkeys[1] =
            bytes(hex"9832164ad7eaeb6e649600d1ff7f25faf1ad7a829b6dc6133011bc38a5920761182a5b861345fb315d16dd0841eebc1a");
        pubkeys[2] =
            bytes(hex"a11d4b964034b0a9a825cd6de67e4f23749f81bc38594b21126ad606e59f1acc2eb64d058f7c9ac662e0f7288c9fbd5e");
        pubkeys[3] =
            bytes(hex"87ad33e8fffe7c62177d2c860228d5de2cd5041484bdbbe05241fa9ef72feb9dbc201010e4ce9e6d1807d08216b22d0a");
        pubkeys[4] =
            bytes(hex"8186b51b20e581a988482f2ab6b1d8084c151fd7eabdc161c5b6a5e512bd098d771c5d96c1ffaabed4a0d570227050fb");
        vm.prank(_controllerAddress);
        largeStaking.registerValidator(1, pubkeys, signatures, depositDataRoots);
        checkStakingInfo(1, false, 1, 960 ether, 160 ether, 0, 0);

        uint256 pledgeBalance = 0;
        uint256 requirBalance = 0;
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(1 ether, pledgeBalance);

        pubkeys[0] =
            bytes(hex"a51358e07d52a08bc4fdc6b0e17e5a5d543955cddbf5ad1c371006a706d83db86ba9c1f4f37d07c2455ed8ec1956cd07");
        pubkeys[1] =
            bytes(hex"af9de2b0d1700e3a3757293c4162e59b793e455d6ffdf1db956dc431ae4fedaed1ce6b94bf403c2f274d188ad99f0ec8");
        pubkeys[2] =
            bytes(hex"81b1688beb9bf70dd4a6ee13bb687444344e8345bbfc6a8a81d2562ab429673c8306581a6482934650cff5866004cea5");
        pubkeys[3] =
            bytes(hex"b727b205d752f10cfbc515ac68646ed27b984bc70f278e46054a750f597b9d6d93c51987bac8cf0c9c11decb3be652a0");
        pubkeys[4] =
            bytes(hex"8def5a22758d73598ae964fa71be5fb6c4cc2e1f098e10cb2f0fef2d498a8acfd9554c9b6f9b20d2a2fe613ccea94656");
        vm.prank(_controllerAddress3);
        largeStaking.registerValidator(2, pubkeys, signatures, depositDataRoots);

        checkStakingInfo(2, true, operatorId, 320 ether, 160 ether, 0, 0);

        CLStakingExitInfo[] memory _clStakingExitInfo = new CLStakingExitInfo[] (2);
        CLStakingSlashInfo[] memory _clStakingSlashInfo = new CLStakingSlashInfo[] (2);
        bytes[] memory ps = new bytes[] (2);
        ps[0] =
            bytes(hex"9200d672c314c389a88c1d7695d790ec73181cc60978c548c80c3c4787ee8da817e38904e3d0b6105679ba7f2e4f3d7a");
        ps[1] =
            bytes(hex"9832164ad7eaeb6e649600d1ff7f25faf1ad7a829b6dc6133011bc38a5920761182a5b861345fb315d16dd0841eebc1a");
        _clStakingExitInfo[0] = CLStakingExitInfo({stakingId: 1, pubkeys: ps});
        _clStakingSlashInfo[0] = CLStakingSlashInfo({
            stakingId: 1,
            slashAmount: 1 ether,
            pubkey: bytes(
                hex"9200d672c314c389a88c1d7695d790ec73181cc60978c548c80c3c4787ee8da817e38904e3d0b6105679ba7f2e4f3d7a"
                )
        });
        bytes[] memory ps2 = new bytes[] (2);
        ps2[0] = pubkeys[0];
        ps2[1] = pubkeys[1];
        _clStakingExitInfo[1] = CLStakingExitInfo({stakingId: 2, pubkeys: ps2});
        _clStakingSlashInfo[1] = CLStakingSlashInfo({stakingId: 2, slashAmount: 1 ether, pubkey: pubkeys[0]});

        vm.prank(address(withdrawOracle));
        largeStaking.reportCLStakingData(_clStakingExitInfo, _clStakingSlashInfo);

        checkStakingInfo(1, false, 1, 960 ether, 160 ether, 64 ether, 64 ether);
        checkStakingInfo(2, true, operatorId, 320 ether, 160 ether, 64 ether, 64 ether);

        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(0 ether, pledgeBalance);

        assertEq(operatorSlash.stakingWillCompensated(1), 0 ether);
        assertEq(operatorSlash.stakingHasCompensated(1), 1 ether);
        assertEq(operatorSlash.stakingWillCompensated(2), 0 ether);
        assertEq(operatorSlash.stakingHasCompensated(2), 1 ether);
        assertEq(0, operatorSlash.operatorCompensatedIndex());
        assertEq(0, operatorSlash.stakingCompensatedIndex());
        operatorRegistry.deposit{value: 5 ether}(1);
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(5 ether, pledgeBalance);

        assertEq(operatorSlash.stakingWillCompensated(2), 0 ether);
        assertEq(operatorSlash.stakingHasCompensated(2), 1 ether);
        assertEq(0, operatorSlash.operatorCompensatedIndex());
        assertEq(0, operatorSlash.stakingCompensatedIndex());

        assertEq(0 ether, address(1001).balance);
        assertEq(0 ether, address(1000).balance);
        largeStaking.claimRewardsOfUser(1, 0 ether);
        largeStaking.claimRewardsOfUser(2, 0 ether);
        assertEq(1 ether, address(1001).balance);
        assertEq(1 ether, address(1000).balance);

        assertEq(largeStaking.getOperatorValidatorCounts(1), 30 - 2);
        assertEq(largeStaking.getOperatorValidatorCounts(2), 10 - 2);
    }

    function registerOperator() public returns (uint256) {
        address[] memory _rewardAddresses3 = new address[] (3);
        uint256[] memory _ratios3 = new uint256[] (3);
        _rewardAddresses3[0] = address(70);
        _rewardAddresses3[1] = address(71);
        _rewardAddresses3[2] = address(72);
        _ratios3[0] = 70;
        _ratios3[1] = 20;
        _ratios3[2] = 10;

        address _controllerAddress3 = address(80);
        address _owner3 = address(81);

        uint256 operatorId = operatorRegistry.registerOperator{value: 100 ether}(
            "test1", _controllerAddress3, _owner3, _rewardAddresses3, _ratios3
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(operatorId);
        return operatorId;
    }

    function registerValidator1() public {
        bytes[] memory pubkeys = new bytes[](5);
        bytes[] memory signatures = new bytes[](5);
        bytes32[] memory depositDataRoots = new bytes32[](5);

        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        signatures[0] = sign;
        depositDataRoots[0] = root;
        signatures[1] = sign;
        depositDataRoots[1] = root;
        signatures[2] = sign;
        depositDataRoots[2] = root;
        signatures[3] = sign;
        depositDataRoots[3] = root;
        signatures[4] = sign;
        depositDataRoots[4] = root;
        pubkeys[0] =
            bytes(hex"9200d672c314c389a88c1d7695d790ec73181cc60978c548c80c3c4787ee8da817e38904e3d0b6105679ba7f2e4f3d7a");
        pubkeys[1] =
            bytes(hex"9832164ad7eaeb6e649600d1ff7f25faf1ad7a829b6dc6133011bc38a5920761182a5b861345fb315d16dd0841eebc1a");
        pubkeys[2] =
            bytes(hex"a11d4b964034b0a9a825cd6de67e4f23749f81bc38594b21126ad606e59f1acc2eb64d058f7c9ac662e0f7288c9fbd5e");
        pubkeys[3] =
            bytes(hex"87ad33e8fffe7c62177d2c860228d5de2cd5041484bdbbe05241fa9ef72feb9dbc201010e4ce9e6d1807d08216b22d0a");
        pubkeys[4] =
            bytes(hex"8186b51b20e581a988482f2ab6b1d8084c151fd7eabdc161c5b6a5e512bd098d771c5d96c1ffaabed4a0d570227050fb");
        vm.prank(address(80));
        largeStaking.registerValidator(1, pubkeys, signatures, depositDataRoots);
    }

    function registerValidator2() public {
        bytes[] memory pubkeys = new bytes[](5);
        bytes[] memory signatures = new bytes[](5);
        bytes32[] memory depositDataRoots = new bytes32[](5);

        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        signatures[0] = sign;
        depositDataRoots[0] = root;
        signatures[1] = sign;
        depositDataRoots[1] = root;
        signatures[2] = sign;
        depositDataRoots[2] = root;
        signatures[3] = sign;
        depositDataRoots[3] = root;
        signatures[4] = sign;
        depositDataRoots[4] = root;
        pubkeys[0] =
            bytes(hex"940e72e632c583a6408508b7b44e652e8df5d44500b9a7ac973eb745c8384ac0af47f42c3bedf1c0c6a108e161417644");
        pubkeys[1] =
            bytes(hex"85b439eb322da37c2ad5464fbdff59c02605e87f482a757290dc122e6e8ad357ee6a65e7c0bfff15640ab4635f08d980");
        pubkeys[2] =
            bytes(hex"8795a9313c70d890c83487f0678d4029a5d446dc14e1c4a174d7f1994cbcb0e10273c132289b662c11167d2e8cdf05d0");
        pubkeys[3] =
            bytes(hex"b2644215136c7f2f40984ccb38d350ee4a6a5588117002b484973c1f9ef6e6fff03fc67726958ee1f4dfe126f17ccbc3");
        pubkeys[4] =
            bytes(hex"941ec8768f177fe3df50c0016314e19fc76cf49877e9b0e7eceaf55a86f6cbe2b93925eca52bb0c3d7a916097746c47a");
        vm.prank(address(80));
        largeStaking.registerValidator(2, pubkeys, signatures, depositDataRoots);
    }

    function registerValidator3() public {
        bytes[] memory pubkeys = new bytes[](5);
        bytes[] memory signatures = new bytes[](5);
        bytes32[] memory depositDataRoots = new bytes32[](5);

        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        signatures[0] = sign;
        depositDataRoots[0] = root;
        signatures[1] = sign;
        depositDataRoots[1] = root;
        signatures[2] = sign;
        depositDataRoots[2] = root;
        signatures[3] = sign;
        depositDataRoots[3] = root;
        signatures[4] = sign;
        depositDataRoots[4] = root;
        pubkeys[0] =
            bytes(hex"8cdc04bde1a2dc4ba76ae49868404288c43c1d2dbf5ddad2b15515090de3518e3a73eb6102d81eaaf9e0bbea74091dc6");
        pubkeys[1] =
            bytes(hex"b356b100d56ddd40b0db8627c7e4d19bb826525916fa8f72f5f378a1e2abd24ba7828b005ba1cce021c9059c71ebec3e");
        pubkeys[2] =
            bytes(hex"a13519e896849440bed8a2bde763d857490c3a24c9209ba0b057c086f1b7455eb82540a415187655593d4639997ebc59");
        pubkeys[3] =
            bytes(hex"a4886aa0756c23afecef392b69d091a0a4c450e8805422a46cddb5416e40ada47e3216db62fcbc8873c86819a2ea8878");
        pubkeys[4] =
            bytes(hex"8a7dad13cb2d198b2c5773fc9dfcf92bffbb994ca46ca3798c6efe4b308097cb0760505cb748525e8c20bc155d675239");
        vm.prank(address(80));
        largeStaking.registerValidator(3, pubkeys, signatures, depositDataRoots);
    }

    function testLargeStakingAll() public {
        uint256 operatorId = registerOperator();

        vm.deal(address(1000), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 960 ether}(
            operatorId, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false
        );
        checkStakingInfo(1, false, operatorId, 960 ether, 0, 0, 0);

        // shared reward
        vm.prank(address(81));
        largeStaking.startupSharedRewardPool(operatorId);

        vm.deal(address(1001), 640 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 640 ether}(
            operatorId, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true
        );
        checkStakingInfo(2, true, operatorId, 640 ether, 0, 0, 0);

        registerValidator1();
        checkStakingInfo(1, false, operatorId, 960 ether, 160 ether, 0, 0);

        registerValidator2();
        checkStakingInfo(2, true, operatorId, 640 ether, 160 ether, 0, 0);

        uint256 userReward = largeStaking.reward(2);
        assertEq(0 ether, userReward);

        // reward
        (uint256 operatorId2, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(2);
        console.log("operatorId2", operatorId2);
        console.log("rewardPoolAddr2", rewardPoolAddr);
        console.log("rewards2", rewards);
        vm.deal(address(rewardPoolAddr), 10 ether);

        userReward = largeStaking.reward(2);
        assertEq(9 ether, userReward);

        vm.deal(address(1002), 320 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1002));
        largeStaking.largeStake{value: 320 ether}(
            operatorId, address(1002), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true
        );
        checkStakingInfo(3, true, operatorId, 320 ether, 0, 0, 0);

        // largeStake will settle

        assertEq(largeStaking.daoSharedRewards(operatorId), 0.3 ether);
        assertEq(largeStaking.operatorSharedRewards(operatorId), 0.7 ether);
        assertEq(largeStaking.unclaimedSharedRewards(operatorId), 10 ether);

        registerValidator3();
        checkStakingInfo(3, true, operatorId, 320 ether, 160 ether, 0, 0);

        // operator claim

        uint256[] memory _privatePoolStakingIds = new uint256[] (1);
        _privatePoolStakingIds[0] = 1;
        largeStaking.claimRewardsOfOperator(operatorId, _privatePoolStakingIds);
        assertEq(0.49 ether, address(70).balance); // 0.7 * 0.7
        assertEq(0.14 ether, address(71).balance); // 0.7 * 0.2
        assertEq(0.07 ether, address(72).balance); // 0.7 * 0.1
        assertEq(largeStaking.unclaimedSharedRewards(operatorId), 9.3 ether);

        assertEq(largeStaking.totalShares(operatorId), 960 ether);

        vm.deal(address(rewardPoolAddr), 19.3 ether);
        // 10 reward, totaoShares = 320 + 640 ether, valuePerShare = 9 ether * 1 ether / 640 ether

        userReward = largeStaking.reward(2);
        assertEq(9 ether + 9 ether * 1 ether / 960 ether * 640 ether / 1 ether, userReward);
        uint256 userReward3 = largeStaking.reward(3);
        assertEq(9 ether * 1 ether / 960 ether * 320 ether / 1 ether, userReward3);

        largeStaking.claimRewardsOfUser(2, userReward);
        assertEq(address(1001).balance, userReward);
        largeStaking.claimRewardsOfUser(3, userReward3);
        assertEq(address(1002).balance, userReward3);

        largeStaking.claimRewardsOfOperator(operatorId, _privatePoolStakingIds);
        assertEq(0.49 ether * 2, address(70).balance); // 0.7 * 0.7
        assertEq(0.14 ether * 2, address(71).balance); // 0.7 * 0.2
        assertEq(0.07 ether * 2, address(72).balance); // 0.7 * 0.1

        assertEq(largeStaking.unclaimedSharedRewards(operatorId), 0.6 ether);

        (uint256 operatorId1, address rewardPoolAddr1, uint256 rewards1) = largeStaking.getRewardPoolInfo(1);
        console.log("operatorId1", operatorId1);
        console.log("rewardPoolAddr1", rewardPoolAddr1);
        console.log("rewards1", rewards1);

        vm.deal(address(rewardPoolAddr1), 10 ether);
        uint256 userReward1 = largeStaking.reward(1);
        assertEq(9 ether, userReward1);

        uint256[] memory _stakingIds = new uint256[] (3);
        _stakingIds[0] = 2;
        _stakingIds[1] = 3;
        _stakingIds[2] = 1;
        largeStaking.claimRewardsOfDao(_stakingIds);
        assertEq(largeStaking.unclaimedSharedRewards(operatorId), 0 ether);
        assertEq(largeStaking.daoVaultAddress().balance, 1.1 ether); //0.6 ether + 0.2 ether+ 0.3 ether

        largeStaking.claimRewardsOfOperator(operatorId, _privatePoolStakingIds);
        assertEq(0.49 ether * 3, address(70).balance); // 0.7 * 0.7
        assertEq(0.14 ether * 3, address(71).balance); // 0.7 * 0.2
        assertEq(0.07 ether * 3, address(72).balance); // 0.7 * 0.1

        largeStaking.claimRewardsOfUser(1, userReward1);
        assertEq(address(1000).balance, userReward1);

        assertEq(address(rewardPoolAddr).balance, 0);
        vm.deal(address(rewardPoolAddr), 10 ether);

        // will settle
        vm.prank(address(1001));
        largeStaking.largeUnstake(2, 320 ether);
        checkStakingInfo(2, true, operatorId, 640 ether, 480 ether, 320 ether, 320 ether);

        assertEq(largeStaking.totalShares(operatorId), 640 ether);

        userReward = largeStaking.reward(2);
        assertEq(9 ether * 1 ether / 960 ether * 640 ether / 1 ether, userReward);
        userReward3 = largeStaking.reward(3);
        assertEq(9 ether * 1 ether / 960 ether * 320 ether / 1 ether, userReward3);
        assertEq(largeStaking.unclaimedSharedRewards(operatorId), 10 ether);

        vm.deal(address(rewardPoolAddr), 20 ether);

        largeStaking.settleElSharedReward(operatorId);

        userReward = largeStaking.reward(2);
        assertEq(
            9 ether * 1 ether / 960 ether * 640 ether / 1 ether + 9 ether * 1 ether / 640 ether * 320 ether / 1 ether,
            userReward
        );
        userReward3 = largeStaking.reward(3);
        assertEq(
            9 ether * 1 ether / 960 ether * 320 ether / 1 ether + 9 ether * 1 ether / 640 ether * 320 ether / 1 ether,
            userReward3
        );
        assertEq(largeStaking.unclaimedSharedRewards(operatorId), 20 ether);

        // claim
        largeStaking.claimRewardsOfOperator(operatorId, _privatePoolStakingIds);
        assertEq(0.49 ether * 5, address(70).balance); // 0.7 * 0.7
        assertEq(0.14 ether * 5, address(71).balance); // 0.7 * 0.2
        assertEq(0.07 ether * 5, address(72).balance); // 0.7 * 0.1
        largeStaking.claimRewardsOfDao(_stakingIds);
        assertEq(largeStaking.daoVaultAddress().balance, 1.7 ether); //0.6 ether + 0.2 ether+ 0.3 ether

        largeStaking.claimRewardsOfUser(
            2, 9 ether * 1 ether / 960 ether * 640 ether / 1 ether + 9 ether * 1 ether / 640 ether * 320 ether / 1 ether
        );
        largeStaking.claimRewardsOfUser(
            3, 9 ether * 1 ether / 960 ether * 320 ether / 1 ether + 9 ether * 1 ether / 640 ether * 320 ether / 1 ether
        );
        assertEq(largeStaking.unclaimedSharedRewards(operatorId), 0 ether);
    }

    function testLargeStakingAll2() public {
        // operator 2

        uint256 operatorId = registerOperator();

        vm.deal(address(1000), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 960 ether}(
            operatorId, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false
        );
        checkStakingInfo(1, false, operatorId, 960 ether, 0, 0, 0);

        // shared reward
        vm.prank(address(81));
        largeStaking.startupSharedRewardPool(operatorId);

        vm.deal(address(1001), 640 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 640 ether}(
            operatorId, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true
        );
        checkStakingInfo(2, true, operatorId, 640 ether, 0, 0, 0);

        uint256 userReward = largeStaking.reward(2);
        assertEq(0 ether, userReward);

        // reward
        (uint256 operatorId2, address rewardPoolAddr, uint256 rewards) = largeStaking.getRewardPoolInfo(2);
        console.log("operatorId2", operatorId2);
        console.log("rewardPoolAddr2", rewardPoolAddr);
        console.log("rewards2", rewards);
        vm.deal(address(rewardPoolAddr), 10 ether);

        userReward = largeStaking.reward(2);
        assertEq(9 ether, userReward);

        // operator 1

        vm.deal(address(1000), 960 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1000));
        largeStaking.largeStake{value: 960 ether}(1, address(1000), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, false);
        checkStakingInfo(3, false, 1, 960 ether, 0, 0, 0);

        // shared reward
        vm.prank(address(_owner));
        largeStaking.startupSharedRewardPool(1);

        vm.deal(address(1001), 640 ether);
        vm.deal(0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, 1);
        vm.prank(address(1001));
        largeStaking.largeStake{value: 640 ether}(1, address(1001), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        checkStakingInfo(4, true, 1, 640 ether, 0, 0, 0);

        uint256 userReward3 = largeStaking.reward(3);
        assertEq(0 ether, userReward3);

        // reward
        (uint256 operatorId3, address rewardPoolAddr3, uint256 rewards3) = largeStaking.getRewardPoolInfo(3);
        console.log("operatorId3", operatorId3);
        console.log("rewardPoolAddr3", rewardPoolAddr3);
        console.log("rewards3", rewards3);
        vm.deal(address(rewardPoolAddr3), 10 ether);

        userReward3 = largeStaking.reward(3);
        assertEq(9 ether, userReward3);

        uint256 userReward4 = largeStaking.reward(4);
        assertEq(0 ether, userReward4);

        // reward
        (uint256 operatorId4, address rewardPoolAddr4, uint256 rewards4) = largeStaking.getRewardPoolInfo(4);
        console.log("operatorId4", operatorId4);
        console.log("rewardPoolAddr4", rewardPoolAddr4);
        console.log("rewards4", rewards4);
        vm.deal(address(rewardPoolAddr4), 10 ether);

        userReward4 = largeStaking.reward(4);
        assertEq(9 ether, userReward4);

        vm.deal(address(1002), 960 ether);
        vm.prank(address(1002));
        largeStaking.largeStake{value: 640 ether}(1, address(1002), 0xF5ade6B61BA60B8B82566Af0dfca982169a470Dc, true);
        checkStakingInfo(5, true, 1, 640 ether, 0, 0, 0);

        uint256 userReward5 = largeStaking.reward(5);
        assertEq(0 ether, userReward5);

        vm.deal(address(rewardPoolAddr4), 20 ether); // 10 + 10 ether

        userReward5 = largeStaking.reward(5);
        assertEq(4.5 ether, userReward5);
        userReward4 = largeStaking.reward(4);
        assertEq(13.5 ether, userReward4);

        // will settle
        vm.prank(address(1002));
        largeStaking.largeUnstake(5, 320 ether);
        checkStakingInfo(5, true, 1, 640 ether, 320 ether, 320 ether, 320 ether);

        userReward5 = largeStaking.reward(5);
        assertEq(4.5 ether, userReward5);
        userReward4 = largeStaking.reward(4);
        assertEq(13.5 ether, userReward4);

        vm.deal(address(rewardPoolAddr4), 30 ether); // 10 + 10 + 10 ether

        userReward5 = largeStaking.reward(5);
        assertEq(7.5 ether, userReward5);
        userReward4 = largeStaking.reward(4);
        assertEq(19.5 ether, userReward4);
    }

    function testFailSSV() public {
        uint64 opId1 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e4255555642646d4a32646a63355a484e4e5669383564554a584f564e6151556f4b613356306145684864546b3054545645644456345743744262326c51615731684f545a51555756474d79396a563059775754464c4d544a4c52474644656e6b314d55677a626e6c3556327378566d4a355131706e5767704364565a5464465a76616a4e794e31647364453435534535454f573942634856795156464d526d356f55584236613346554e464a43526939796256466b636a646a567a4a714e57457a6547786c556d787954335633436e42444c30396e5157524861464e555a553033596b646b6254525a4d554a6a62304e74546d4a785a55356d546a4a51546e5535656b59314e6d5a454e6d6c4a575531425357646b5632706e566e4e4e53544e45556b344b4b325a5561576c6a6545683054564a545747637a64544e724d45526c56453943596e7051646e45726447677a646a686957544e686332526a53464654534452774e546b33513049316357396c5532565055554a614d517031644442585457395a5645567153456b785330637a5557466e62464a714f457058635456426545646b54335631516d707a5a564e3057454a7853584e79566b64614f4556435a575a6f6445526e56554a73596d566a436a6c335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            0
        );
        uint64 opId2 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e4255555642656d633257564e7253544e514e336c524c7a5254576a687363454d4b5a4670316445743565584a454d6d567562464e6c656c6c314f464675536e704d5a6b706d55476459616c464a566c56315231417264486f764f57744f56555a7251314a44595764546547687456476851516d78686377703255584e3463455a795a336876515531444d314e494f4656345a433830564774704e303557597a467661444e7a4c314675644764704d464e554d584679543156534d6c4633596d497a616e4674626c4a7851327330436d68515255746c64334d7a63486877576b317a51334e6c52556c5a615746696244464353546c785a3235566556597752336854526d5a6c5231567164565131516d46726555513356556442616e426f626a5a77636b634b5554564a4d7a4d7a64573533654339475757316861445671616a68754c30707557584d79567a646e5631637665437454526c497a656a457a53574e695a5649335a6d464d4f46566b57484a6d536c5a344c32783553776f304f556475626d644556484a5a6444646b6157777752486b344d555651566e4e6c4e323030655852526157746a4e6b5a75536d68685a6e42556455517861544e494f5641784d564a715154467063307074546d356d436c4e525355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            4591710000000
        );
        uint64 opId3 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556426555347659584a44537a4a614c7a6732616e46745357314c4e46674b61453161575556504e464932616c4a794b33426d546b6c434e544a4d576c527454474e424d7a426c6145526f5a3364795656644c54586f35536b5a45537a557862334a4f6144466f4e46517854324e694b7a51765677704d616e6b7a4f565a4a56325a4b576b4e555a58524c4e546451543370794d457454516c524c553146556345553263316c4a576c557261464a6f5a46684a56305277535535574f45787153474e786247343163315a5a436d7848534849774d5446325333525a4b314e4b61486871616c59765645353056464978564535495958633262306f335955744563577335576c687064576f335356704b4c316870533246585533643361565a6b6257344b636d524b615739746547457a61565a44597a564d51334a565447393653327069636a64774e7a464f55487071546b4e5655554972615770534e465a4465555254556c56715347497853444e794d6974755932647a6441704464445636626b704b614546535a323134546b70774d45747a616d564e543056544f445934566e6331656a4a754c30565a51544179616a525a4e30784a5456424c546d4e44536a686e55306c464b7a6c5865446332436b5a335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            591710000000
        );
        uint64 opId4 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556426358644c65546475576e5a4e4d4455786255746f646e4a515445634b643168314c30744a636d315857574e434d6b705562566449575564795155314e55485231656b55346255467a4e3056555432673252584a71634564735631646b563352734f557442626c6830523170494d46413255676f77636c4534534652465a3078696444524855334257596e525555565535616e425553476836646d39325645705664474a744d5467764e326c7a4e7a5250596c706a546d785763314934545538785554565761326477436c5a45557a5a5a4e544254613077774c30383153476857576d6c78626b56355a326c5254477779636e4e3463574e726446686d4e5452694d3064424c334a4a526c5a4a516c677a596d6c44634338724d7a5a70567a494b626d643463546c6f537a6875646d7070654768614f58427a55453543516a49775a555a476357743361316c6a53565a524d31686b56325255646b464b625374554e574671656a6877527a4a4f52475a46534552704e51707654484e6d566b5a7a5358423457575a32596c426f5a445a3152457847645738344e32686853556b79615739734e6b5a536544644a536d564f6132354b6432597963324e456547357a4b797435517a633459334a6e436d6c525355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            2591710000000
        );
        uint64 opId5 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556424e44426155565272576e4275635864315a577459544556566147384b4d485976646c4245544852564d4531534d31647656576c734d6b465263544e6862316c3554565133596b6c5a536e704e4e4442305a566842544842314d79744e64574a6d4f5842756330744e646b70765757744c6477704e4d6d4a4456325673565778454d335a58615642515256457762306446544535584d6d6c78546c6732576e4e6a56444678536a4232556b4a6a5245524a4e6c4e4259305674576a453253474e7a4d6d45315647525a436d68715331644b4e6939366445356f4d6d5a79576e46594b3052735a6b7447635731544e54457861457335597a56564e793969646a5249556d4a584d554d3463587049595374344f466c6f6256425a613270575a444d4b6557307962437434647a5236626d4a6f4e5774785a6d733262486f7252303933654539306248704d4e303945516c68704f485a534f44527965454e565345303351315a6d546b31455a30526a64444e4d52477432616770745244426f5a6b396e4f56687256485656516b51724f546c4f4f464a57643146706333687463444e4a57555a69576a5251536b5132526d46324d4446445a3245314d476455556a4a3257485a34567a64335648465a436b46335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            15917100000000
        );

        uint64[] memory _operatorIds = new uint64[] (4);
        _operatorIds[0] = opId1;
        _operatorIds[1] = opId2;
        _operatorIds[2] = opId4;
        _operatorIds[3] = opId5;
        vm.prank(_dao);
        ssvManager.setSSVOperator(_operatorIds, true);

        vm.prank(_dao);
        stakingManager.setSSVStakingQuota(1, 63 ether);

        vm.deal(address(21), 32 ether);
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 32 ether}(1);

        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        bytes memory pubkey =
            bytes(hex"b5c28a10ac150d59c7ae852dfdb9155884fae9696bb20aae32195f996b1f2e5720736849da5fd5e92b815648fdae4b61");
        bytes memory sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        bytes32 root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
    }

    function testFailSSV2() public {
        uint64 opId1 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e4255555642646d4a32646a63355a484e4e5669383564554a584f564e6151556f4b613356306145684864546b3054545645644456345743744262326c51615731684f545a51555756474d79396a563059775754464c4d544a4c52474644656e6b314d55677a626e6c3556327378566d4a355131706e5767704364565a5464465a76616a4e794e31647364453435534535454f573942634856795156464d526d356f55584236613346554e464a43526939796256466b636a646a567a4a714e57457a6547786c556d787954335633436e42444c30396e5157524861464e555a553033596b646b6254525a4d554a6a62304e74546d4a785a55356d546a4a51546e5535656b59314e6d5a454e6d6c4a575531425357646b5632706e566e4e4e53544e45556b344b4b325a5561576c6a6545683054564a545747637a64544e724d45526c56453943596e7051646e45726447677a646a686957544e686332526a53464654534452774e546b33513049316357396c5532565055554a614d517031644442585457395a5645567153456b785330637a5557466e62464a714f457058635456426545646b54335631516d707a5a564e3057454a7853584e79566b64614f4556435a575a6f6445526e56554a73596d566a436a6c335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            0
        );
        uint64 opId2 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e4255555642656d633257564e7253544e514e336c524c7a5254576a687363454d4b5a4670316445743565584a454d6d567562464e6c656c6c314f464675536e704d5a6b706d55476459616c464a566c56315231417264486f764f57744f56555a7251314a44595764546547687456476851516d78686377703255584e3463455a795a336876515531444d314e494f4656345a433830564774704e303557597a467661444e7a4c314675644764704d464e554d584679543156534d6c4633596d497a616e4674626c4a7851327330436d68515255746c64334d7a63486877576b317a51334e6c52556c5a615746696244464353546c785a3235566556597752336854526d5a6c5231567164565131516d46726555513356556442616e426f626a5a77636b634b5554564a4d7a4d7a64573533654339475757316861445671616a68754c30707557584d79567a646e5631637665437454526c497a656a457a53574e695a5649335a6d464d4f46566b57484a6d536c5a344c32783553776f304f556475626d644556484a5a6444646b6157777752486b344d555651566e4e6c4e323030655852526157746a4e6b5a75536d68685a6e42556455517861544e494f5641784d564a715154467063307074546d356d436c4e525355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            4591710000000
        );
        uint64 opId3 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556426555347659584a44537a4a614c7a6732616e46745357314c4e46674b61453161575556504e464932616c4a794b33426d546b6c434e544a4d576c527454474e424d7a426c6145526f5a3364795656644c54586f35536b5a45537a557862334a4f6144466f4e46517854324e694b7a51765677704d616e6b7a4f565a4a56325a4b576b4e555a58524c4e546451543370794d457454516c524c553146556345553263316c4a576c557261464a6f5a46684a56305277535535574f45787153474e786247343163315a5a436d7848534849774d5446325333525a4b314e4b61486871616c59765645353056464978564535495958633262306f335955744563577335576c687064576f335356704b4c316870533246585533643361565a6b6257344b636d524b615739746547457a61565a44597a564d51334a565447393653327069636a64774e7a464f55487071546b4e5655554972615770534e465a4465555254556c56715347497853444e794d6974755932647a6441704464445636626b704b614546535a323134546b70774d45747a616d564e543056544f445934566e6331656a4a754c30565a51544179616a525a4e30784a5456424c546d4e44536a686e55306c464b7a6c5865446332436b5a335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            591710000000
        );
        uint64 opId4 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556426358644c65546475576e5a4e4d4455786255746f646e4a515445634b643168314c30744a636d315857574e434d6b705562566449575564795155314e55485231656b55346255467a4e3056555432673252584a71634564735631646b563352734f557442626c6830523170494d46413255676f77636c4534534652465a3078696444524855334257596e525555565535616e425553476836646d39325645705664474a744d5467764e326c7a4e7a5250596c706a546d785763314934545538785554565761326477436c5a45557a5a5a4e544254613077774c30383153476857576d6c78626b56355a326c5254477779636e4e3463574e726446686d4e5452694d3064424c334a4a526c5a4a516c677a596d6c44634338724d7a5a70567a494b626d643463546c6f537a6875646d7070654768614f58427a55453543516a49775a555a476357743361316c6a53565a524d31686b56325255646b464b625374554e574671656a6877527a4a4f52475a46534552704e51707654484e6d566b5a7a5358423457575a32596c426f5a445a3152457847645738344e32686853556b79615739734e6b5a536544644a536d564f6132354b6432597963324e456547357a4b797435517a633459334a6e436d6c525355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            2591710000000
        );
        uint64 opId5 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556424e44426155565272576e4275635864315a577459544556566147384b4d485976646c4245544852564d4531534d31647656576c734d6b465263544e6862316c3554565133596b6c5a536e704e4e4442305a566842544842314d79744e64574a6d4f5842756330744e646b70765757744c6477704e4d6d4a4456325673565778454d335a58615642515256457762306446544535584d6d6c78546c6732576e4e6a56444678536a4232556b4a6a5245524a4e6c4e4259305674576a453253474e7a4d6d45315647525a436d68715331644b4e6939366445356f4d6d5a79576e46594b3052735a6b7447635731544e54457861457335597a56564e793969646a5249556d4a584d554d3463587049595374344f466c6f6256425a613270575a444d4b6557307962437434647a5236626d4a6f4e5774785a6d733262486f7252303933654539306248704d4e303945516c68704f485a534f44527965454e565345303351315a6d546b31455a30526a64444e4d52477432616770745244426f5a6b396e4f56687256485656516b51724f546c4f4f464a57643146706333687463444e4a57555a69576a5251536b5132526d46324d4446445a3245314d476455556a4a3257485a34567a64335648465a436b46335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            15917100000000
        );

        uint64[] memory _operatorIds = new uint64[] (4);
        _operatorIds[0] = opId1;
        _operatorIds[1] = opId2;
        _operatorIds[2] = opId4;
        _operatorIds[3] = opId5;
        vm.prank(_dao);
        ssvManager.setSSVOperator(_operatorIds, true);

        vm.prank(_dao);
        stakingManager.setSSVStakingQuota(1, 63 ether);

        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(1, vnft.getEmptyNftCounts());
        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);
        bytes memory pubkey =
            bytes(hex"a646616d3f394e9addff2d5e6744cf7923347ce5fc8358148875647fe227abe154331a3b3a6312f6f2ef39dd746c7ca8");
        bytes memory sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        bytes32 root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(0, vnft.getEmptyNftCounts());

        assertEq(vnft.validatorsOfOperator(1).length, 1);

        ssvManager.startupSSV(1);
        address ssvCluster = ssvManager.getSSVCluster(1);
        ssvToken.transfer(ssvCluster, 100000000000000000000);

        vm.prank(address(_controllerAddress));
        ssvManager.approve(1, 9000000000000000000);

        vm.deal(address(21), 32 ether);
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 32 ether}(1);

        pubkey =
            bytes(hex"b5c28a10ac150d59c7ae852dfdb9155884fae9696bb20aae32195f996b1f2e5720736849da5fd5e92b815648fdae4b61");
        sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");

        ISSV.Cluster memory cluster =
            ISSV.Cluster({validatorCount: 0, networkFeeIndex: 0, index: 0, active: true, balance: 0});
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        _operatorIds[3] = opId3;
        stakingManager.registerSSVValidator(
            pubkey, sign, root, _operatorIds, bytes("sharesData"), 9000000000000000000, cluster
        );
    }

    function testSSV() public {
        uint64 opId1 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e4255555642646d4a32646a63355a484e4e5669383564554a584f564e6151556f4b613356306145684864546b3054545645644456345743744262326c51615731684f545a51555756474d79396a563059775754464c4d544a4c52474644656e6b314d55677a626e6c3556327378566d4a355131706e5767704364565a5464465a76616a4e794e31647364453435534535454f573942634856795156464d526d356f55584236613346554e464a43526939796256466b636a646a567a4a714e57457a6547786c556d787954335633436e42444c30396e5157524861464e555a553033596b646b6254525a4d554a6a62304e74546d4a785a55356d546a4a51546e5535656b59314e6d5a454e6d6c4a575531425357646b5632706e566e4e4e53544e45556b344b4b325a5561576c6a6545683054564a545747637a64544e724d45526c56453943596e7051646e45726447677a646a686957544e686332526a53464654534452774e546b33513049316357396c5532565055554a614d517031644442585457395a5645567153456b785330637a5557466e62464a714f457058635456426545646b54335631516d707a5a564e3057454a7853584e79566b64614f4556435a575a6f6445526e56554a73596d566a436a6c335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            0
        );
        uint64 opId2 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e4255555642656d633257564e7253544e514e336c524c7a5254576a687363454d4b5a4670316445743565584a454d6d567562464e6c656c6c314f464675536e704d5a6b706d55476459616c464a566c56315231417264486f764f57744f56555a7251314a44595764546547687456476851516d78686377703255584e3463455a795a336876515531444d314e494f4656345a433830564774704e303557597a467661444e7a4c314675644764704d464e554d584679543156534d6c4633596d497a616e4674626c4a7851327330436d68515255746c64334d7a63486877576b317a51334e6c52556c5a615746696244464353546c785a3235566556597752336854526d5a6c5231567164565131516d46726555513356556442616e426f626a5a77636b634b5554564a4d7a4d7a64573533654339475757316861445671616a68754c30707557584d79567a646e5631637665437454526c497a656a457a53574e695a5649335a6d464d4f46566b57484a6d536c5a344c32783553776f304f556475626d644556484a5a6444646b6157777752486b344d555651566e4e6c4e323030655852526157746a4e6b5a75536d68685a6e42556455517861544e494f5641784d564a715154467063307074546d356d436c4e525355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            4591710000000
        );
        uint64 opId3 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556426555347659584a44537a4a614c7a6732616e46745357314c4e46674b61453161575556504e464932616c4a794b33426d546b6c434e544a4d576c527454474e424d7a426c6145526f5a3364795656644c54586f35536b5a45537a557862334a4f6144466f4e46517854324e694b7a51765677704d616e6b7a4f565a4a56325a4b576b4e555a58524c4e546451543370794d457454516c524c553146556345553263316c4a576c557261464a6f5a46684a56305277535535574f45787153474e786247343163315a5a436d7848534849774d5446325333525a4b314e4b61486871616c59765645353056464978564535495958633262306f335955744563577335576c687064576f335356704b4c316870533246585533643361565a6b6257344b636d524b615739746547457a61565a44597a564d51334a565447393653327069636a64774e7a464f55487071546b4e5655554972615770534e465a4465555254556c56715347497853444e794d6974755932647a6441704464445636626b704b614546535a323134546b70774d45747a616d564e543056544f445934566e6331656a4a754c30565a51544179616a525a4e30784a5456424c546d4e44536a686e55306c464b7a6c5865446332436b5a335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            591710000000
        );
        uint64 opId4 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556426358644c65546475576e5a4e4d4455786255746f646e4a515445634b643168314c30744a636d315857574e434d6b705562566449575564795155314e55485231656b55346255467a4e3056555432673252584a71634564735631646b563352734f557442626c6830523170494d46413255676f77636c4534534652465a3078696444524855334257596e525555565535616e425553476836646d39325645705664474a744d5467764e326c7a4e7a5250596c706a546d785763314934545538785554565761326477436c5a45557a5a5a4e544254613077774c30383153476857576d6c78626b56355a326c5254477779636e4e3463574e726446686d4e5452694d3064424c334a4a526c5a4a516c677a596d6c44634338724d7a5a70567a494b626d643463546c6f537a6875646d7070654768614f58427a55453543516a49775a555a476357743361316c6a53565a524d31686b56325255646b464b625374554e574671656a6877527a4a4f52475a46534552704e51707654484e6d566b5a7a5358423457575a32596c426f5a445a3152457847645738344e32686853556b79615739734e6b5a536544644a536d564f6132354b6432597963324e456547357a4b797435517a633459334a6e436d6c525355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            2591710000000
        );
        uint64 opId5 = ssvNetwork.registerOperator(
            bytes(
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000002644c5330744c5331435255644a54694253553045675546564354456c4449457446575330744c533074436b314a53554a4a616b464f516d64726357687261556335647a424351564646526b464254304e425554684254556c4a516b4e6e53304e42555556424e44426155565272576e4275635864315a577459544556566147384b4d485976646c4245544852564d4531534d31647656576c734d6b465263544e6862316c3554565133596b6c5a536e704e4e4442305a566842544842314d79744e64574a6d4f5842756330744e646b70765757744c6477704e4d6d4a4456325673565778454d335a58615642515256457762306446544535584d6d6c78546c6732576e4e6a56444678536a4232556b4a6a5245524a4e6c4e4259305674576a453253474e7a4d6d45315647525a436d68715331644b4e6939366445356f4d6d5a79576e46594b3052735a6b7447635731544e54457861457335597a56564e793969646a5249556d4a584d554d3463587049595374344f466c6f6256425a613270575a444d4b6557307962437434647a5236626d4a6f4e5774785a6d733262486f7252303933654539306248704d4e303945516c68704f485a534f44527965454e565345303351315a6d546b31455a30526a64444e4d52477432616770745244426f5a6b396e4f56687256485656516b51724f546c4f4f464a57643146706333687463444e4a57555a69576a5251536b5132526d46324d4446445a3245314d476455556a4a3257485a34567a64335648465a436b46335355524255554643436930744c5330745255354549464a545153425156554a4d53554d675330565a4c5330744c53304b00000000000000000000000000000000000000000000000000000000"
            ),
            15917100000000
        );

        uint64[] memory _operatorIds = new uint64[] (4);
        _operatorIds[0] = opId1;
        _operatorIds[1] = opId2;
        _operatorIds[2] = opId4;
        _operatorIds[3] = opId5;
        vm.prank(_dao);
        ssvManager.setSSVOperator(_operatorIds, true);

        vm.prank(_dao);
        stakingManager.setSSVStakingQuota(1, 63 ether);

        vm.deal(address(74), 32 ether);
        vm.prank(address(74));
        vm.deal(0xB553A401FBC2427777d05ec21Dd37a03e1FA6894, 1 wei);
        liquidStaking.stakeNFT{value: 32 ether}(1, 0xB553A401FBC2427777d05ec21Dd37a03e1FA6894);
        assertEq(1, vnft.balanceOf(address(74)));
        assertEq(0, neth.balanceOf(address(74)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(32 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(1, vnft.getEmptyNftCounts());
        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);
        bytes memory pubkey =
            bytes(hex"a646616d3f394e9addff2d5e6744cf7923347ce5fc8358148875647fe227abe154331a3b3a6312f6f2ef39dd746c7ca8");
        bytes memory sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        bytes32 root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(0 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0 ether, liquidStaking.operatorNftPoolBalances(1));
        assertEq(0, vnft.getEmptyNftCounts());

        assertEq(vnft.validatorsOfOperator(1).length, 1);

        vm.prank(address(_owner));
        ssvManager.startupSSV(1);
        address ssvCluster = ssvManager.getSSVCluster(1);
        ssvToken.transfer(ssvCluster, 100000000000000000000);

        vm.prank(address(_controllerAddress));
        ssvManager.approve(1, 9000000000000000000);

        vm.deal(address(21), 64 ether);
        vm.prank(address(21));
        liquidStaking.stakeETH{value: 64 ether}(1);

        pubkey =
            bytes(hex"b5c28a10ac150d59c7ae852dfdb9155884fae9696bb20aae32195f996b1f2e5720736849da5fd5e92b815648fdae4b61");
        sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");

        ISSV.Cluster memory cluster =
            ISSV.Cluster({validatorCount: 0, networkFeeIndex: 0, index: 0, active: true, balance: 0});
        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerSSVValidator(
            pubkey, sign, root, _operatorIds, bytes("sharesData"), 9000000000000000000, cluster
        );

        assertEq(stakingManager.ssvStakingQuota(1), 31 ether);

        pubkey =
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
        sign = bytes(
            hex"87a834c348fe64fd8ead55299ded58ce58fb529326c89a57efcc184e067d29fd89ab6fedf70d722bffbbe0ebfd4beff10810bdfa2a588bf89697273c501b28c3ee04c895c4fcba8d1b193c9416d6808f3eebff8f7be66601a390a2d9d940e253"
        );
        root = bytes32(hex"13881d4f72c54a43ca210b3766659c28f3fe959ea36e172369813c603d197845");

        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        stakingManager.registerValidator(pubkeys, signatures, depositDataRoots);
    }

    function testFailTransfer() public {
        vm.prank(address(_owner));
        ssvManager.startupSSV(1);
        address ssvCluster = ssvManager.getSSVCluster(1);
        ssvToken.transfer(ssvCluster, 100000000000000000000);

        vm.prank(address(_controllerAddress));
        ssvManager.approve(1, 9000000000000000000);

        vm.prank(address(_controllerAddress));
        ssvManager.transfer(1, address(1), 10000000000000000000);
    }

    function testTransfer() public {
        vm.prank(address(_owner));
        ssvManager.startupSSV(1);
        address ssvCluster = ssvManager.getSSVCluster(1);
        ssvToken.transfer(ssvCluster, 100000000000000000000);

        vm.prank(address(_controllerAddress));
        ssvManager.approve(1, 9000000000000000000);

        vm.prank(address(_owner));
        ssvManager.transfer(1, address(1), 10000000000000000000);
    }

    function testSetSSVOperator() public {
        uint64[] memory _ssvOps = new uint64[] (6);
        _ssvOps[0] = 1;
        _ssvOps[1] = 2;
        _ssvOps[2] = 3;
        _ssvOps[3] = 4;
        _ssvOps[4] = 5;
        _ssvOps[5] = 6;
        vm.prank(address(_dao));
        ssvManager.setSSVOperator(_ssvOps, true);
        assertEq(ssvManager.ssvOperatorWhitelist(1), true);
        assertEq(ssvManager.ssvOperatorWhitelist(2), true);
        assertEq(ssvManager.ssvOperatorWhitelist(3), true);
        assertEq(ssvManager.ssvOperatorWhitelist(4), true);
        assertEq(ssvManager.ssvOperatorWhitelist(5), true);
        assertEq(ssvManager.ssvOperatorWhitelist(6), true);

        vm.prank(address(_dao));
        ssvManager.setSSVOperator(_ssvOps, false);
        assertEq(ssvManager.ssvOperatorWhitelist(1), false);
        assertEq(ssvManager.ssvOperatorWhitelist(2), false);
        assertEq(ssvManager.ssvOperatorWhitelist(3), false);
        assertEq(ssvManager.ssvOperatorWhitelist(4), false);
        assertEq(ssvManager.ssvOperatorWhitelist(5), false);
        assertEq(ssvManager.ssvOperatorWhitelist(6), false);
    }

    function testSetDaoAddress() public {
        ssvManager.setDaoAddress(address(1));
        assertEq(ssvManager.dao(), address(1));
    }

    function testSetSSVOperatorPermissionless() public {
        vm.prank(address(_dao));
        ssvManager.setSSVOperatorPermissionless(true);
        assertEq(ssvManager.permissionless(), true);

        vm.prank(address(_dao));
        ssvManager.setSSVOperatorPermissionless(false);
        assertEq(ssvManager.permissionless(), false);
    }
}
