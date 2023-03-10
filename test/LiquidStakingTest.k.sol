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
import "src/vault/ELVault.sol";
import "src/mocks/DepositContract.sol";
import "../src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVaultFactory.sol";

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
    event RewardClaimed(address _owner, uint256 _amount);

    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    NodeOperatorRegistry operatorRegistry;
    BeaconOracle beaconOracle;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;

    address _dao = address(1);
    address _daoVaultAddress = address(2);
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
    address _oracleMember1 = address(11);
    address _oracleMember2 = address(12);
    address _oracleMember3 = address(13);
    address _oracleMember4 = address(14);
    address _oracleMember5 = address(15);
    address[] _rewardAddresses = new address[] (2);
    uint256[] _ratios = new uint256[] (2);
    bytes withdrawalCreds = hex"00baaf6f093e5f5ea02487e58fbc2733b6716b106ceb2bc9fa95e454fb25b4d0";
    bytes tempSignature =
        hex"b6f352fbd336da8a0d7ba52e0a42d31d207cafac2694f200da9d867e74ca9b5c5ccff6277bb091c57b954cbefc76764802d3bf47602070dca2abce2085af039f14983c082c27038d9c8a012aa6ff48d85886dd638520f7b1bd9ecfa041d56310";
    bytes32 tempDepositDataRoot = hex"b19b9c1e5c576ac4af90e281617de1e0e949968c0a343d821a5383a6997f4964";
    bytes pubKey = hex"90e8c1460fdb55b944ad4b9ec73275c2ef701311715d6f8766a02d0b0b8f37a21c871fdc9784276ec74515e7a219cbcf";
    bytes32 merkleTreeRoot = 0x847e7dedeae2fdb5b098c298e3aff134d9cc0a8d61126631f7bfe43b7ba1dfe4;

    function setUp() public {
        _rewardAddresses[0] = address(5);
        _rewardAddresses[1] = address(6);
        _ratios[0] = 100;
        _ratios[1] = 0;
        liquidStaking = new LiquidStaking();

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();

        vaultFactoryContract = new ELVaultFactory();
        vaultFactoryContract.initialize(address(vaultContract), address(vnft), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoVaultAddress, address(vaultFactoryContract), address(vnft));
        vm.prank(_dao);
        operatorRegistry.setLiquidStaking(address(liquidStaking));
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

        depositContract = new DepositContract();

        vm.warp(1673161943);
        beaconOracle = new BeaconOracle();
        // goerli: 1616508000
        // mainnet: 1606824023
        uint64 genesisTime = 1616508000;
        beaconOracle.initialize(_dao, genesisTime, address(vnft));
        vm.startPrank(_dao);
        beaconOracle.addOracleMember(_oracleMember1);
        beaconOracle.setLiquidStaking(address(liquidStaking));
        vm.stopPrank();

        liquidStaking.initialize(
            _dao,
            _daoVaultAddress,
            withdrawalCreds,
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(beaconOracle),
            address(depositContract)
        );

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "one", _controllerAddress, address(4), _rewardAddresses, _ratios
        );

        operatorRegistry.registerOperator{value: 1.1 ether}("two", address(888), address(4), _rewardAddresses, _ratios);

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);
    }

    function testInitialize() public {
        liquidStaking = new LiquidStaking();

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();

        vaultFactoryContract = new ELVaultFactory();
        vaultFactoryContract.initialize(address(vaultContract), address(vnft), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoVaultAddress, address(vaultFactoryContract), address(vnft));
        vm.prank(_dao);
        operatorRegistry.setLiquidStaking(address(liquidStaking));
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

        depositContract = new DepositContract();

        vm.warp(1673161943);
        beaconOracle = new BeaconOracle();

        uint64 genesisTime = 1616508000;
        beaconOracle.initialize(_dao, genesisTime, address(vnft));

        vm.startPrank(_dao);
        beaconOracle.addOracleMember(_oracleMember1);
        vm.stopPrank();

        liquidStaking.initialize(
            _dao,
            _daoVaultAddress,
            withdrawalCreds,
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

    function testSetDaoAddress() public {
        liquidStaking.setDaoAddress(address(10));
        assertEq(liquidStaking.dao(), address(10));
    }

    function testAssignBlacklistOrQuitOperator() public {
        uint256[] memory _operatorIdsToAllocateShare = new uint256[] (1);
        _operatorIdsToAllocateShare[0] = uint256(1);

        uint256[] memory _shareAmounts = new uint256[] (1);
        _shareAmounts[0] = uint256(0);

        vm.expectEmit(true, true, false, false, address(liquidStaking));
        emit BlacklistOperatorAssigned(2, 0);

        liquidStaking.assignBlacklistOrQuitOperator(
            2, // blacklisted operator
            _operatorIdsToAllocateShare,
            _shareAmounts
        );
    }

    function testFailSetDepositFeeRate(uint256 feeRate) public {
        vm.assume(feeRate > 1000);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(feeRate);
        failed();
    }

    function testSetDepositFeeRate(uint256 feeRate) public {
        vm.assume(feeRate < 1000);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(feeRate);
        assertEq(liquidStaking.depositFeeRate(), feeRate);
    }

    function testGetEthOut(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 gwei);
        vm.assume(nethAmount < 1000000 ether);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        liquidStaking.stakeETH{value: (nethAmount)}(1);
        uint256 ethValue;
        ethValue = liquidStaking.getEthOut(nethAmount);
        uint256 totalEth = liquidStaking.getTotalEthValue();
        uint256 nethSupply = neth.totalSupply();
        uint256 selfCalculated = nethAmount * (totalEth) / (nethSupply);
        assertEq(ethValue, selfCalculated);
    }

    function testGetNethValue(uint256 ethAmount) public {
        vm.assume(ethAmount > 1000 gwei);
        vm.assume(ethAmount < 1000000 ether);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        liquidStaking.stakeETH{value: (ethAmount)}(1);
        uint256 nethValue;
        nethValue = liquidStaking.getNethOut(ethAmount);

        uint256 totalEth = liquidStaking.getTotalEthValue();
        uint256 nethSupply = neth.totalSupply();
        uint256 selfCalculated = ethAmount * (nethSupply) / (totalEth);
        assertEq(nethValue, selfCalculated);
    }

    function testGetExchangeRate(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 gwei);
        vm.assume(nethAmount < 1000000 ether);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(1000);
        liquidStaking.stakeETH{value: (nethAmount)}(1);
        uint256 ethValue;
        ethValue = liquidStaking.getExchangeRate();
        uint256 totalEth = liquidStaking.getTotalEthValue();
        uint256 nethSupply = neth.totalSupply();
        uint256 selfCalculated = (1 ether) * (totalEth) / (nethSupply);
        assertEq(ethValue, selfCalculated);
    }

    function testStakeEthWithDiscount(uint256 nethAmount) public {
        vm.assume(nethAmount > 1000 gwei);
        vm.assume(nethAmount < 1000000 ether);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(1000);
        liquidStaking.stakeETH{value: (nethAmount)}(1);
        uint256 ethValue;
        uint256 calculatedValue;
        ethValue = liquidStaking.getTotalEthValue();
        calculatedValue = beaconOracle.getBeaconBalances() + (nethAmount - ((nethAmount * 1000) / 10000));
        assertEq(ethValue, calculatedValue);
    }

    function testStakeNFT() public {
        vm.prank(address(2));
        vm.deal(address(2), 32 ether);
        liquidStaking.stakeNFT{value: 32 ether}(1);
    }

    function testWrapNFT() public {
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        vm.deal(address(22), 32 ether);
        vm.prank(address(22));
        liquidStaking.stakeETH{value: 32 ether}(1);

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

        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = 0xea3006ad05e29fa6c4558dcd2d21ff22a7c5b73f7e349c80a0c14d75f4c76433;

        vm.startPrank(address(liquidStaking));
        uint256 tokenId = vnft.whiteListMint(bytes("2"), address(2), 1);

        assertEq(vnft.tokenOfValidator(pubkey), 0);
        assertEq(vnft.validatorOf(0), pubkey);

        vm.stopPrank();

        vm.prank(_oracleMember1);
        beaconOracle.reportBeacon(147375, 65000000000000000000, 2, merkleTreeRoot);
        uint256 _value = 32000000000000000000;
        bool ok = beaconOracle.verifyNftValue(_proof, pubkey, _value, 0);

        vm.prank(address(22));
        neth.approve(address(liquidStaking), 100 ether);
        vm.prank(address(22));
        liquidStaking.wrapNFT(0, _proof, 32 ether);
    }

    function testUnwrapNFT() public {
        bytes[] memory pubkeys = new bytes[](1);
        bytes[] memory signatures = new bytes[](1);
        bytes32[] memory depositDataRoots = new bytes32[](1);

        vm.deal(address(22), 32 ether);
        vm.prank(address(22));
        liquidStaking.stakeNFT{value: 32 ether}(1);

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

        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = 0xea3006ad05e29fa6c4558dcd2d21ff22a7c5b73f7e349c80a0c14d75f4c76433;

        vm.startPrank(address(liquidStaking));
        uint256 tokenId = vnft.whiteListMint(bytes("2"), address(2), 1);

        assertEq(vnft.tokenOfValidator(pubkey), 0);
        assertEq(vnft.validatorOf(0), pubkey);

        vm.stopPrank();

        vm.prank(_oracleMember1);
        beaconOracle.reportBeacon(147375, 65000000000000000000, 2, merkleTreeRoot);
        uint256 _value = 32000000000000000000;
        bool ok = beaconOracle.verifyNftValue(_proof, pubkey, _value, 0);

        vm.prank(address(22));
        liquidStaking.unwrapNFT(0, _proof, _value);
    }

    function testGetNFTOut() public {
        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = 0xea3006ad05e29fa6c4558dcd2d21ff22a7c5b73f7e349c80a0c14d75f4c76433;
        bytes memory pubkey =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");

        vm.startPrank(address(liquidStaking));
        vnft.whiteListMint(pubkey, address(2), 1);
        vnft.whiteListMint(bytes("2"), address(2), 1);
        vm.stopPrank();
        vm.prank(_oracleMember1);
        beaconOracle.reportBeacon(147375, 65000000000000000000, 2, merkleTreeRoot);
        assertEq(vnft.validatorOf(0), pubkey);
        uint256 _value = 32000000000000000000;

        uint256 nftOut = liquidStaking.getNFTOut(0, _proof, _value);
        uint256 nethOut = liquidStaking.getNethOut(_value);
        assertEq(nftOut, nethOut);
    }

    function testBatchReinvestmentRewardsOfOperator() public {
        uint256[] memory operatorIds = new uint256[](1);
        operatorIds[0] = 1;
        // no reward, no emit
        // vm.expectEmit(true, true, false, false);
        // emit RewardsReceive(0);
        // vm.expectEmit(false, false, false, false);
        // emit RewardClaimed(address(liquidStaking), 0);
        // vm.expectEmit(true, true, false, false);
        // emit OperatorReinvestRewards(1, 0);
        liquidStaking.batchReinvestRewardsOfOperator(operatorIds);
    }

    function testClaimRewardsOfUser() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x2d17183ec955000e448f9ba74cb9cfec4690d35ed96aef6901f68892b38ae58e;
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        vm.prank(address(2));
        vm.deal(address(2), 1000000 ether);
        liquidStaking.stakeETH{value: 1000 ether}(1);

        bytes[] memory localpk = new bytes[](1);
        bytes[] memory localSig = new bytes[](1);
        bytes32[] memory localDataRoot = new bytes32[](1);
        localpk[0] = pubKey;
        localSig[0] = tempSignature;
        localDataRoot[0] = tempDepositDataRoot;

        vm.prank(_controllerAddress);
        liquidStaking.registerValidator(localpk, localSig, localDataRoot);
        vm.prank(address(3));
        vm.deal(address(3), 1000000 ether);
        liquidStaking.stakeETH{value: 1000 ether}(1);
        uint256[] memory tokenIds = vnft.tokensOfOwner(address(liquidStaking));
        address vaultContractAddress = operatorRegistry.getNodeOperatorVaultContract(1);
        vm.prank(address(liquidStaking));
        IELVault(vaultContractAddress).setUserNft(tokenIds[0], 1000);
        vm.deal(address(vaultContractAddress), 10 ether);
        vm.prank(address(liquidStaking));
        IELVault(vaultContractAddress).settle();
        // liquidStaking.claimRewardsOfUser must be called by the user
        // liquidStaking.claimRewardsOfUser(tokenIds[0]);
    }

    function testClaimOperaterRewards() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x2d17183ec955000e448f9ba74cb9cfec4690d35ed96aef6901f68892b38ae58e;
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        vm.prank(address(2));
        vm.deal(address(2), 1000000 ether);
        liquidStaking.stakeETH{value: 1000 ether}(1);

        bytes[] memory localpk = new bytes[](1);
        bytes[] memory localSig = new bytes[](1);
        bytes32[] memory localDataRoot = new bytes32[](1);
        localpk[0] = pubKey;
        localSig[0] = tempSignature;
        localDataRoot[0] = tempDepositDataRoot;

        vm.prank(_controllerAddress);
        liquidStaking.registerValidator(localpk, localSig, localDataRoot);
        vm.prank(address(3));
        vm.deal(address(3), 1000000 ether);
        liquidStaking.stakeETH{value: 1000 ether}(1);
        uint256[] memory tokenIds = vnft.tokensOfOwner(address(liquidStaking));
        console.log("tokenIds.length");
        console.log(tokenIds.length);
        console.log("tokenIds[0]");
        console.log(tokenIds[0]);
        console.log("vaultContractAddress");
        console.log(address(vaultContract));
        address vaultContractAddress = operatorRegistry.getNodeOperatorVaultContract(1);
        vm.prank(address(liquidStaking));
        IELVault(vaultContractAddress).setUserNft(tokenIds[0], 1000);
        operatorRegistry.claimRewardsOfOperator(1);
    }

    function testClaimDaoRewards() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x2d17183ec955000e448f9ba74cb9cfec4690d35ed96aef6901f68892b38ae58e;
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        vm.prank(address(2));
        vm.deal(address(2), 1000000 ether);
        liquidStaking.stakeETH{value: 1000 ether}(1);

        bytes[] memory localpk = new bytes[](1);
        bytes[] memory localSig = new bytes[](1);
        bytes32[] memory localDataRoot = new bytes32[](1);
        localpk[0] = pubKey;
        localSig[0] = tempSignature;
        localDataRoot[0] = tempDepositDataRoot;

        vm.prank(_controllerAddress);
        liquidStaking.registerValidator(localpk, localSig, localDataRoot);
        vm.prank(address(3));
        vm.deal(address(3), 1000000 ether);
        liquidStaking.stakeETH{value: 1000 ether}(1);
        uint256[] memory tokenIds = vnft.tokensOfOwner(address(liquidStaking));
        address vaultContractAddress = operatorRegistry.getNodeOperatorVaultContract(1);
        vm.prank(address(liquidStaking));
        IELVault(vaultContractAddress).setUserNft(tokenIds[0], 1000);
        operatorRegistry.claimRewardsOfDao(1);
    }

    function testGetNethOut(uint256 ethAmount) public {
        vm.assume(ethAmount > 1000 gwei);
        vm.assume(ethAmount < 1000000 ether);
        liquidStaking.setDaoAddress(_dao);
        vm.prank(_dao);
        liquidStaking.setDepositFeeRate(0);
        liquidStaking.stakeETH{value: (ethAmount)}(1);
        uint256 nethValue;
        nethValue = liquidStaking.getNethOut(ethAmount);
        uint256 totalEth = liquidStaking.getTotalEthValue();
        uint256 nethSupply = neth.totalSupply();
        uint256 selfCalculated = ethAmount * (nethSupply) / (totalEth);
        assertEq(nethValue, selfCalculated);
    }

    // function test_authorizeUpgrade(address randomAdd) public {
    //     vm.prank(address(liquidStaking));
    //     vm.expectRevert("Not supported yet");
    //     liquidStaking._authorizeUpgrade(randomAdd);
    // }

    function testUnstakeNFT(uint256 randomInt) public {
        bool isTrue = liquidStaking.unstakeNFT(1);
        assertEq(true, isTrue);
    }

    function testSetBeaconOracleContract(uint256 randomInt) public {
        // bytes[] memory data = new bytes[](0);
        // bool isTrue = liquidStaking.unstakeNFT(data);
        // assertEq(true, isTrue);
        BeaconOracle tempBeaconOracle = new BeaconOracle();
        vm.prank(_dao);
        liquidStaking.setBeaconOracleContract(address(tempBeaconOracle));
        assertEq(address(liquidStaking.beaconOracleContract()), address(tempBeaconOracle));
    }

    function testSetNodeOperatorRegistryContract(uint256 randomInt) public {
        NodeOperatorRegistry tempOperatorRegistry = new NodeOperatorRegistry();
        vm.prank(_dao);
        liquidStaking.setNodeOperatorRegistryContract(address(tempOperatorRegistry));
        assertEq(address(liquidStaking.nodeOperatorRegistryContract()), address(tempOperatorRegistry));
    }

    // function testUnstakeETHWithDiscount(uint256 nethAmount) public {
    //     vm.assume(nethAmount > 1000 gwei);
    //     vm.assume(nethAmount < 1000000 ether);
    //     liquidStaking.setDaoAddress(_dao);
    //     liquidStaking.setDepositFeeRate(1000);
    //     liquidStaking.stakeETH{value: (nethAmount)}(1);
    //     uint256[] memory operatorIds = new uint256[](1);
    //     liquidStaking.batchClaimRewardsOfOperator(operatorIds);
    //     // uint256 ethValue;
    //     uint256 calculatedValue;
    //     // ethValue = liquidStaking.getTotalEthValue();
    //     calculatedValue = (nethAmount - ((nethAmount * 1000) / 10000));
    //     liquidStaking.unstakeETH(calculatedValue);
    //     // assertEq(ethValue, calculatedValue);
    // }

    // function testMint(uint256 ethAmount) public {
    //     ExpectEmit emitter = new ExpectEmit();

    //     liquidStaking.initialize(
    //         withdrawalCreds, address(nodeOperatorRegistry), nethAddress, beaconOracleContractAdd, validatorNftAdd
    //     );
    //     liquidStaking.setDepositFeeRate(0);
    //     liquidStaking.stakeETH{value: 1000000 ether}( 0);
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
    //     liquidStaking.stakeETH{value: 1000000 ether}(0);
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
