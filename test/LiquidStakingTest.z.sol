// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/vault/ELVault.sol";
import "src/oracles/BeaconOracle.sol";
import "forge-std/console.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/ConsensusVault.sol";

contract LiquidStakingTest is Test {
    event OperatorRegister(string _name, address _controllerAddress, address _owner, uint256 operatorId);
    event OperatorWithdraw(uint256 operatorId, uint256 withdrawAmount, address to);
    event OperatorQuit(uint256 operatorId, uint256 substituteOperatorId, uint256 nowVault, address to);
    event BlacklistOperatorAssigned(uint256 blacklistOperatorId, uint256 totalAmount);
    event EthStake(address indexed from, uint256 amount, uint256 amountOut);
    event EthUnstake(address indexed from, uint256 amount, uint256 amountOut);
    event NftStake(address indexed from, uint256 count);
    event ValidatorRegistered(uint256 operator, uint256 tokenId);
    event NftWrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event NftUnwrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event UserClaimRewards(uint256 operatorId, uint256 rewards);
    event Transferred(address _to, uint256 _amount);
    event NFTMinted(uint256 tokenId);
    event OperatorReinvestRewards(uint256 operatorId, uint256 rewards);
    event OperatorClaimRewards(uint256 operatorId, uint256 rewards);
    event DaoClaimRewards(uint256 operatorId, uint256 rewards);
    event RewardsReceive(uint256 rewards);
    event SlashReceive(uint256 amount);

    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    NodeOperatorRegistry operatorRegistry;
    BeaconOracle beaconOracle;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    ConsensusVault consensusVaultContract;
    address payable consensusVaultContractAddr;

    address _dao = address(1);
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
        vaultFactoryContract.initialize(address(vaultContract), address(vnft), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress, address(vaultFactoryContract), address(vnft));
        vm.prank(_dao);
        operatorRegistry.setLiquidStaking(address(liquidStaking));
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

        depositContract = new DepositContract();

        vm.warp(1673161943);
        beaconOracle = new BeaconOracle();
        // goerli: 1616508000
        // mainnet: 1606824023
        uint64 genesisTime = 1616508000;
        beaconOracle.initialize(_dao, genesisTime);
        vm.startPrank(_dao);
        beaconOracle.addOracleMember(_oracleMember1);
        beaconOracle.addOracleMember(_oracleMember2);
        beaconOracle.addOracleMember(_oracleMember3);
        beaconOracle.addOracleMember(_oracleMember4);
        beaconOracle.addOracleMember(_oracleMember5);
        beaconOracle.setLiquidStaking(address(liquidStaking));
        vm.stopPrank();

        liquidStaking.initialize(
            _dao,
            _daoValutAddress,
            hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106",
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(beaconOracle),
            address(depositContract)
        );

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "one", _controllerAddress, address(4), _rewardAddresses, _ratios
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);
    }

    function testStakeETH() public {
        vm.expectEmit(true, true, false, true);
        emit EthStake(address(20), 1 ether, 1 ether);
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
        emit NftStake(address(20), 10);
        vm.prank(address(20));
        vm.deal(address(20), 330 ether);
        vm.roll(10000);

        liquidStaking.stakeNFT{value: 320 ether}(1);
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
    }

    function testStakeNFT2() public {
        vm.prank(address(20));
        vm.roll(10000);

        liquidStaking.stakeNFT{value: 0 ether}(1);
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
        liquidStaking.stakeNFT{value: 32 ether}(1);
        assertEq(1, vnft.balanceOf(address(21)));
        assertEq(0, neth.balanceOf(address(21)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(32 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(64 ether, liquidStaking.operatorPoolBalances(1));

        address operatorVaultAddr = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("operatorVaultAddr: ", operatorVaultAddr);
        console.log("operatorVaultImpl: ", address(vaultContract));

        vm.deal(address(operatorVaultAddr), 1 ether);
        vm.roll(20000);

        vm.deal(address(22), 32 ether);
        vm.prank(address(22));
        liquidStaking.stakeNFT{value: 32 ether}(1);
        assertEq(1, vnft.balanceOf(address(22)));
        assertEq(0, neth.balanceOf(address(22)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(96 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(address(21).balance, 0);
        assertEq(address(22).balance, 0);

        liquidStaking.claimRewardsOfUser(0);
        liquidStaking.claimRewardsOfUser(1);
        assertEq(address(22).balance, 0);
        assertEq(address(21).balance, 0.9 ether);
        assertEq(IELVault(operatorVaultAddr).getLiquidStakingReward(), 0);

        assertEq(96 ether, liquidStaking.operatorPoolBalances(1));

        vm.deal(address(23), 33 ether);
        vm.prank(address(23));
        liquidStaking.stakeETH{value: 32 ether}(1);
        assertEq(0, vnft.balanceOf(address(23)));
        assertEq(32 ether, neth.balanceOf(address(23)));
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(128 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);

        assertEq(32 ether, neth.balanceOf(address(23)));
        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        assertEq(liquidStaking.getNethOut(1 ether), 1 ether);
        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        // registerValidator
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        vm.prank(_dao);
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

        assertEq(96 ether, liquidStaking.operatorPoolBalances(1));

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 0);

        vm.prank(_dao);
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

        assertEq(0, vnft.balanceOf(address(liquidStaking)));
        assertEq(64 ether, neth.balanceOf(address(liquidStaking)));

        assertEq(vnft.validatorExists(pubkey), true);
        assertEq(vnft.tokenOfValidator(pubkey), 1);
        assertEq(64 ether, liquidStaking.operatorPoolBalances(1));
        assertEq(liquidStaking.getEthOut(1 ether), 1 ether);
        // unwrapNFT todo
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

        vm.prank(_dao);
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
        operatorRegistry.registerOperator{value: 1.1 ether}(
            "33woqwertyuuoionkonkonkonkonkonkd", _controllerAddress, _owner, _rewardAddresses, _ratios
        );
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
        assertEq(6 ether, operatorRegistry.getPledgeBalanceOfOperator(operatorId));
        assertEq(false, operatorRegistry.isQuitOperator(operatorId));
        vm.prank(_owner);
        operatorRegistry.withdrawOperator(operatorId, 1 ether, _to);
        assertEq(5 ether, operatorRegistry.getPledgeBalanceOfOperator(operatorId));
        assertEq(_to.balance, 1 ether);

        assertEq(false, operatorRegistry.isQuitOperator(operatorId));
        vm.prank(_owner);
        operatorRegistry.quitOperator(operatorId, _to);
        assertEq(0 ether, operatorRegistry.getPledgeBalanceOfOperator(operatorId));
        assertEq(_to.balance, 6 ether);
        assertEq(true, operatorRegistry.isQuitOperator(operatorId));

        operatorRegistry.deposit{value: 5 ether}(operatorId);
        assertEq(5 ether, operatorRegistry.getPledgeBalanceOfOperator(operatorId));
        assertEq(false, operatorRegistry.isQuitOperator(operatorId));

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

        assertEq(5 ether, operatorRegistry.getPledgeBalanceOfOperator(operatorId));
        vm.prank(_owner);
        operatorRegistry.withdrawOperator(operatorId, 1 ether, _to);
        assertEq(_to.balance, 7 ether);

        vm.prank(_dao);
        operatorRegistry.removeBlacklistOperator(operatorId);
        assertEq(true, operatorRegistry.isTrustedOperator(operatorId));
        assertEq(2, operatorRegistry.isTrustedOperatorOfControllerAddress(_controllerAddress));
        assertEq(4 ether, operatorRegistry.getPledgeBalanceOfOperator(operatorId));

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
        operatorRegistry.withdrawOperator(operatorId, 3.9 ether, _to);
        assertEq(0.1 ether, operatorRegistry.getPledgeBalanceOfOperator(operatorId));
        assertEq(false, operatorRegistry.isConformBasicPledge(operatorId));
        assertEq(_to.balance, 10.9 ether);

        vm.prank(_dao);
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

        operatorRegistry.claimRewardsOfOperator(operatorId);
        operatorRegistry.claimRewardsOfDao(operatorId);
    }

    function testSetpermissionlessBlockNumber() public {
        vm.prank(_dao);
        operatorRegistry.setpermissionlessBlockNumber(1000000);
        assertEq(1000000, operatorRegistry.permissionlessBlockNumber());
        vm.expectRevert("The permissionless phase has begun");
        vm.prank(_dao);
        operatorRegistry.setpermissionlessBlockNumber(2000000);
    }

    function testConsensusVault() public {
        consensusVaultContractAddr.transfer(100 ether);
        assertEq(100 ether, address(consensusVaultContract).balance);

        vm.prank(address(liquidStaking));
        consensusVaultContract.transfer(50 ether, address(60));
        assertEq(50 ether, address(consensusVaultContract).balance);
        assertEq(50 ether, address(60).balance);

        vm.prank(_dao);
        consensusVaultContract.setLiquidStaking(address(61));
        assertEq(consensusVaultContract.liquidStakingContractAddress(), address(61));
    }

    function testELVaultFactory() public {
        vaultFactoryContract.setNodeOperatorRegistry(address(70));
        assertEq(vaultFactoryContract.nodeOperatorRegistryAddress(), address(70));
    
        vm.expectRevert("Not allowed to create vault");
        vaultFactoryContract.create(2);

        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));
        vm.prank(address(operatorRegistry));
        address vaultAddress = vaultFactoryContract.create(2);
    }

    

}
