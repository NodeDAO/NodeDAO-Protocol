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
import {WithdrawInfo, ExitValidatorInfo} from "src/library/ConsensusStruct.sol";
import "src/OperatorSlash.sol";
import "src/WithdrawalRequest.sol";

contract LiquidStakingTest is Test, MockOracleProvider {
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
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    ConsensusVault consensusVaultContract;
    address payable consensusVaultContractAddr;
    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;

    HashConsensusWithTimer consensus;

    address _dao = DAO;
    address _daoValutAddress = address(2);
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
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

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"0100000000000000000000006ae2f56c057e31a18224dbc6ae32b0a5fbedfcb0")
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

        assertEq(64 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(64 ether, liquidStaking.operatorNftPoolBalances(1)); // 62 + 32 - 32

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(0, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 2); // already 0, 1

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000d9e2dc13b0d2f6f73cd21c32fbf7de143c558e29")
        );
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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

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

        assertEq(2, operatorRegistry.getNodeOperatorsCount());
        assertEq(0, operatorRegistry.getBlacklistOperatorsCount());

        vm.prank(_dao);
        operatorRegistry.setBlacklistOperator(operatorId);
        assertEq(false, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(0, operatorRegistry.isTrustedOperatorOfControllerAddress(_controllerAddress));
        assertEq(2, operatorRegistry.getNodeOperatorsCount());
        assertEq(1, operatorRegistry.getBlacklistOperatorsCount());

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

        vm.prank(_owner);
        operatorRegistry.setNodeOperatorName(operatorId, "test2");
        checkOperator(operatorId, true, "test2", address(40), _owner);

        _rewardAddresses2[0] = address(45);
        _rewardAddresses2[1] = address(46);
        _rewardAddresses2[2] = address(47);
        _ratios2[0] = 50;
        _ratios2[1] = 30;
        _ratios2[2] = 20;

        vm.prank(_owner);
        operatorRegistry.setNodeOperatorRewardAddress(operatorId, _rewardAddresses2, _ratios2);
        (address[] memory rewardAddresses3, uint256[] memory ratios3) =
            operatorRegistry.getNodeOperatorRewardSetting(operatorId);
        assertEq(rewardAddresses3[0], _rewardAddresses2[0]);
        assertEq(rewardAddresses3[1], _rewardAddresses2[1]);
        assertEq(rewardAddresses3[2], _rewardAddresses2[2]);
        assertEq(ratios3[0], _ratios2[0]);
        assertEq(ratios3[1], _ratios2[1]);
        assertEq(ratios3[2], _ratios2[2]);

        _controllerAddress = address(48);
        vm.prank(_owner);
        operatorRegistry.setNodeOperatorControllerAddress(operatorId, _controllerAddress);
        checkOperator(operatorId, true, "test2", address(48), _owner);
        assertEq(0, operatorRegistry.isTrustedOperatorOfControllerAddress(address(40)));
        assertEq(2, operatorRegistry.isTrustedOperatorOfControllerAddress(address(48)));

        vm.prank(_owner);
        operatorRegistry.setNodeOperatorOwnerAddress(operatorId, address(49));
        _owner = address(49);
        checkOperator(operatorId, true, "test2", address(48), _owner);

        console.log("getNodeOperatorVaultContract", operatorRegistry.getNodeOperatorVaultContract(operatorId));
        assertEq(address(49), operatorRegistry.getNodeOperatorOwner(operatorId));

        assertEq(true, operatorRegistry.isConformBasicPledge(operatorId));
        vm.prank(_owner);
        operatorRegistry.withdrawOperator(operatorId, 3 ether, _to);
        (pledgeBalance, requirBalance) = operatorRegistry.getPledgeInfoOfOperator(operatorId);
        assertEq(1 ether, pledgeBalance);
        assertEq(true, operatorRegistry.isConformBasicPledge(operatorId));
        assertEq(_to.balance, 5 ether);

        operatorRegistry.setDaoAddress(address(50));
        assertEq(operatorRegistry.dao(), address(50));
        _dao = address(50);

        vm.prank(_dao);
        operatorRegistry.setDaoVaultAddress(address(51));
        assertEq(operatorRegistry.daoVaultAddress(), address(51));

        assertEq(operatorRegistry.registrationFee(), 0.1 ether);
        vm.prank(_dao);
        operatorRegistry.setRegistrationFee(1 ether);
        assertEq(operatorRegistry.registrationFee(), 1 ether);

        vm.prank(_dao);
        operatorRegistry.setpermissionlessBlockNumber(1000000);
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

    function testSetpermissionlessBlockNumber() public {
        vm.prank(_dao);
        operatorRegistry.setpermissionlessBlockNumber(1000000);
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
        vm.prank(address(_controllerAddress3));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

        address vaultContractAddress;
        (,,,, vaultContractAddress) = operatorRegistry.getNodeOperator(operatorId, false);

        assertEq(address(vaultContractAddress).balance, 0);
        payable(vaultContractAddress).transfer(10 ether);
        assertEq(address(vaultContractAddress).balance, 10 ether);

        assertEq(32 ether, liquidStaking.operatorPoolBalances(operatorId));
        vm.roll(200);

        // registerValidator 2
        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000d9e2dc13b0d2f6f73cd21c32fbf7de143c558e29")
        );
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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
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
        assertEq(3 ether, vaultManager.rewards(tokenIds));

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

        assertEq(3 ether, vaultManager.rewards(tokenIds));

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

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"0100000000000000000000006ae2f56c057e31a18224dbc6ae32b0a5fbedfcb0")
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
        vm.prank(address(_controllerAddress3));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

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

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000d9e2dc13b0d2f6f73cd21c32fbf7de143c558e29")
        );
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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
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
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 0.1 ether);

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
        operatorRegistry.setVaultFactorContract(address(vaultFactoryContract2));
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

        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000d9e2dc13b0d2f6f73cd21c32fbf7de143c558e29")
        );
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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
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
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 64.1 ether);

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
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 63.6 ether);

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
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 61.6 ether);

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
            bytes(hex"b54ee87c9c125925dcab01d3849fd860bf048abc0ace753f717ee1bc12e640d9a32477757e90c3478a7879e6920539a2");
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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
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
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");
        sign = bytes(
            hex"8c9270550945d18f6500e11d0db074d52408cde8a3a30108c8e341ba6e0b92a4d82efb24097dc808313a0145ba096e0c16455aa1c3a7a1019ae34ddf540d9fa121e498c43f757bc6f4105fe31dd5ea8d67483ab435e5a371874dddffa5e65b58"
        );
        root = bytes32(hex"2c6181bcae0df24f047332b10657ee75faa7c42657b6577d7efac6672376bc33");
        pubkeys[0] = pubkey;
        signatures[0] = sign;
        depositDataRoots[0] = root;

        assertEq(vnft.validatorExists(pubkey), false);
        vm.prank(address(_controllerAddress));
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);
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
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 0.1 ether);
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
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 0.1 ether);
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
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 200, slashAmount: 3 ether});
        uint256[] memory empty = new uint256[] (0);

        vm.roll(210);

        vm.deal(address(consensusVaultContract), 0.1 ether);

        vm.prank(address(withdrawOracle));
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 0.1 ether);
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
        assertEq(2 ether, operatorSlash.nftWillCompensated(1));
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
        assertEq(3 ether, operatorSlash.nftHasCompensated(1));
        assertEq(2, operatorSlash.operatorCompensatedIndex());
        tokenIds[0] = 1;
        vaultManager.claimRewardsOfUser(tokenIds);
        assertEq(3 ether, address(24).balance);
        assertEq(0, operatorSlash.nftHasCompensated(1));
        assertEq(2, operatorSlash.operatorCompensatedIndex());
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(1 ether, balance);
    }

    function testValidatorSlash6() public {
        _stakeUserValidator();

        WithdrawInfo[] memory _withdrawInfo = new WithdrawInfo[] (1);
        _withdrawInfo[0] = WithdrawInfo({operatorId: 1, clReward: 0.1 ether, clCapital: 0 ether});
        ExitValidatorInfo[] memory _exitValidatorInfo = new ExitValidatorInfo[] (2);
        _exitValidatorInfo[0] = ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 7300, slashAmount: 0 ether});
        _exitValidatorInfo[1] = ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 7300, slashAmount: 0 ether});
        uint256[] memory empty = new uint256[] (0);
        uint256[] memory _userNftExitDelayedTokenIds = new uint256[] (2);
        _userNftExitDelayedTokenIds[0] = 0;
        _userNftExitDelayedTokenIds[1] = 1;

        vm.roll(200);
        vm.prank(address(74));
        uint256[] memory tokenids = new uint256[] (1);
        tokenids[0] = 0;
        withdrawalRequest.unstakeNFT(tokenids);
        tokenids[0] = 1;
        vm.prank(address(24));
        withdrawalRequest.unstakeNFT(tokenids);

        vm.deal(address(consensusVaultContract), 0.1 ether);

        assertEq(0, liquidStaking.operatorPoolBalances(1));

        vm.prank(address(withdrawOracle));

        vm.roll(7400);
        uint256 slashAmount = 2000000000000 * 7200;
        vaultManager.reportConsensusData(
            _withdrawInfo, _exitValidatorInfo, _userNftExitDelayedTokenIds, empty, 0.1 ether
        );
        assertEq(0 ether, address(74).balance);
        assertEq(0, address(operatorSlash).balance);
        assertEq(slashAmount * 2 + 0.1 ether, liquidStaking.operatorPoolBalances(1));
    }

    function testValidatorSlash7() public {
        _stakePoolValidator();

        vm.deal(address(76), 32 ether);
        vm.prank(address(76));
        liquidStaking.stakeETH{value: 32 ether}(1);

        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);
        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000b553a401fbc2427777d05ec21dd37a03e1fa6894")
        );

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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

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
        uint256[] memory empty = new uint256[] (0);
        uint256[] memory _largeExitDelayedRequestIds = new uint256[] (2);
        _largeExitDelayedRequestIds[0] = 0;
        _largeExitDelayedRequestIds[1] = 1;

        vm.deal(address(consensusVaultContract), 96.1 ether);

        vm.prank(address(withdrawOracle));

        vm.roll(7400);
        uint256 slashAmount = 2000000000000 * 7200;
        vaultManager.reportConsensusData(
            _withdrawInfo, _exitValidatorInfo, empty, _largeExitDelayedRequestIds, 96.1 ether
        );

        assertEq(0 ether, address(75).balance);
        assertEq(0 ether, address(76).balance);
        assertEq(0, address(operatorSlash).balance);
        assertEq(72 ether, address(withdrawalRequest).balance);
        assertEq(slashAmount * 2 + 24.1 ether, liquidStaking.operatorPoolBalances(1));

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
        assertEq(1 ether - slashAmount * 2, balance);
    }

    function testValidatorSlash8() public {
        _stakePoolValidator();

        vm.deal(address(76), 32 ether);
        vm.prank(address(76));
        liquidStaking.stakeETH{value: 32 ether}(1);

        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);
        liquidStaking.setLiquidStakingWithdrawalCredentials(
            bytes(hex"010000000000000000000000b553a401fbc2427777d05ec21dd37a03e1fa6894")
        );

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
        liquidStaking.registerValidator(pubkeys, signatures, depositDataRoots);

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
        uint256[] memory empty = new uint256[] (0);
        uint256[] memory _largeExitDelayedRequestIds = new uint256[] (2);
        _largeExitDelayedRequestIds[0] = 0;
        _largeExitDelayedRequestIds[1] = 1;

        vm.deal(address(consensusVaultContract), 96.1 ether);

        vm.prank(address(withdrawOracle));
        vm.roll(7400);
        uint256 slashAmount = 2000000000000 * 7200;
        vaultManager.reportConsensusData(_withdrawInfo, _exitValidatorInfo, empty, empty, 96.1 ether);

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
        vaultManager.reportConsensusData(
            _withdrawInfo2, _exitValidatorInfo2, empty, _largeExitDelayedRequestIds, 0 ether
        );
        assertEq(slashAmount * 2 + 24.1 ether, liquidStaking.operatorPoolBalances(1));
        uint256 balance;
        (balance,) = operatorRegistry.getPledgeInfoOfOperator(1);
        assertEq(1 ether - slashAmount * 2, balance);
    }

}
