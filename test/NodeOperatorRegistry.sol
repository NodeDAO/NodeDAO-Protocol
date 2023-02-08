// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/vault/ELVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/oracles/BeaconOracle.sol";

contract NodeOperatorRegistryTest is Test {
    event NodeOperatorRegistered(
        uint256 id,
        string name,
        address controllerAddress,
        address _vaultContractAddress,
        address[] _rewardAddresses,
        uint256[] _ratios
    );
    event NodeOperatorTrustedSet(uint256 id, string name, bool trusted);
    event NodeOperatorTrustedRemove(uint256 id, string name, bool trusted);
    event NodeOperatorBlacklistSet(uint256 id);
    event NodeOperatorBlacklistRemove(uint256 id);
    event NodeOperatorNameSet(uint256 id, string name);
    event NodeOperatorRewardAddressSet(uint256 id, address[] _rewardAddresses, uint256[] _ratios);
    event NodeOperatorControllerAddressSet(uint256 id, string name, address controllerAddress);
    event NodeOperatorOwnerAddressSet(uint256 id, string name, address ownerAddress);
    event Transferred(address _to, uint256 _amount);
    event Slashed(uint256 _amount, uint256 _operatorId);
    event Deposited(uint256 _amount, uint256 _operatorId);
    event Withdraw(uint256 _amount, uint256 _operatorId, address _to);
    event LiquidStakingChanged(address _from, address _to);
    event PermissionlessBlockNumberSet(uint256 blockNumber);

    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    BeaconOracle beaconOracle;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    NodeOperatorRegistry operatorRegistry;

    address _dao = address(1);
    address _daoVaultAddress = address(2);
    address _rewardAddress = address(3);
    address _controllerAddress = address(4);
    address _referral = address(5);
    address _oracleMember1 = address(11);
    address _oracleMember2 = address(12);
    address _oracleMember3 = address(13);
    address _oracleMember4 = address(14);
    address _oracleMember5 = address(15);
    address[] _rewardAddresses = new address[] (1);
    uint256[] _ratios = new uint256[] (1);

    function checkOperator(bool _trusted, string memory _name, address _controllerAddr, address _owner) public {
        bool trusted;
        string memory name;
        address owner;
        address controllerAddress;
        address vaultContractAddress;
        (trusted, name, owner, controllerAddress, vaultContractAddress) = operatorRegistry.getNodeOperator(1, true);
        assertEq(trusted, _trusted);
        assertEq(name, _name);
        assertEq(owner, _owner);
        assertEq(controllerAddress, _controllerAddr);
        console.log("vaultContractAddress: ", vaultContractAddress);
    }

    function setUp() public {
        _rewardAddresses[0] = address(5);
        _ratios[0] = 100;

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
        operatorRegistry.initialize(_dao, _daoVaultAddress, address(vaultFactoryContract));
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
        vm.stopPrank();

        liquidStaking.initialize(
            _dao,
            _daoVaultAddress,
            hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106",
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(beaconOracle),
            address(depositContract)
        );
    }

    function testDao() public {
        assertEq(operatorRegistry.dao(), _dao);
        assertEq(operatorRegistry.daoVaultAddress(), _daoVaultAddress);
    }

    // -------------

    function testFailRegisterOperator() public {
        liquidStaking.registerOperator{value: 0.09 ether}("one", address(3), address(4), _rewardAddresses, _ratios);
    }

    function testRegisterOperator() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);
    }

    // -------------

    function testSetTrustedOperatorAuthFailed() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);

        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.setTrustedOperator(0);
    }

    function testSetTrustedOperatorNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(0);
    }

    function testSetTrustedOperator() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        checkOperator(true, "one", address(3), address(4));
    }

    // -------------

    function testRemoveTrustedOperatorAuthFailed() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);

        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.removeTrustedOperator(0);
    }

    function testRemoveTrustedOperatorNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(_dao);
        operatorRegistry.removeTrustedOperator(0);
    }

    function testRemoveTrustedOperator() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);
        vm.prank(_dao);
        operatorRegistry.removeTrustedOperator(1);

        checkOperator(false, "one", address(3), address(4));
    }

    // -------------

    function testSetNodeOperatorNameAuthFailed() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);

        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.setNodeOperatorName(1, "two");
    }

    function testSetNodeOperatorNameNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorName(1, "two");
    }

    function testSetNodeOperatorName() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorName(1, "two");

        checkOperator(false, "two", address(3), address(4));
    }

    // -------------

    function testSetNodeOperatorRewardAddressAuthFailed() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);

        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.setNodeOperatorRewardAddress(1, _rewardAddresses, _ratios);
    }

    function testSetNodeOperatorRewardAddressNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorRewardAddress(1, _rewardAddresses, _ratios);
    }

    function testSetNodeOperatorRewardAddressName() public {
        // vm.expectEmit(true, true, false, true);
        // emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        // emit Transferred(address(1), 0.1 ether);
        // emit NodeOperatorNameSet(0, "two");

        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorRewardAddress(1, _rewardAddresses, _ratios);

        checkOperator(false, "one", address(3), address(4));
    }

    // -------------

    function testSetNodeOperatorControllerAddressAuthFailed() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);

        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.setNodeOperatorControllerAddress(1, address(5));
    }

    function testSetNodeOperatorControllerAddressNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorControllerAddress(1, address(5));
    }

    function testSetNodeOperatorControllerAddressName() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);
        checkOperator(false, "one", address(3), address(4));
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorControllerAddress(1, address(5));

        checkOperator(false, "one", address(5), address(4));
    }

    function testGetNodeOperatorsCount() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(4), address(3), _rewardAddresses, _ratios);
        uint256 count = operatorRegistry.getNodeOperatorsCount();
        assertEq(count, 1);
        address vaultContractAddress = operatorRegistry.getNodeOperatorVaultContract(1);
        console.log("vaultContractAddress: ", vaultContractAddress);

        liquidStaking.registerOperator{value: 1.1 ether}("one", address(5), address(3), _rewardAddresses, _ratios);
        address vaultContractAddress2 = operatorRegistry.getNodeOperatorVaultContract(2);
        console.log("vaultContractAddress2: ", vaultContractAddress2);

        liquidStaking.registerOperator{value: 1.1 ether}("one", address(6), address(3), _rewardAddresses, _ratios);
        address vaultContractAddress3 = operatorRegistry.getNodeOperatorVaultContract(3);
        console.log("vaultContractAddress3: ", vaultContractAddress3);

        liquidStaking.registerOperator{value: 1.1 ether}("one", address(7), address(3), _rewardAddresses, _ratios);
        address vaultContractAddress4 = operatorRegistry.getNodeOperatorVaultContract(4);
        console.log("vaultContractAddress4: ", vaultContractAddress4);

        count = operatorRegistry.getNodeOperatorsCount();
        assertEq(count, 4);
    }

    // -------------

    function testIsTrustedOperatorNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.isTrustedOperator(0);
    }

    function testTrustedOperator() public {
        liquidStaking.registerOperator{value: 1.1 ether}("one", address(3), address(4), _rewardAddresses, _ratios);

        bool trused = operatorRegistry.isTrustedOperator(1);
        assertEq(trused, false);

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        trused = operatorRegistry.isTrustedOperator(1);
        assertEq(trused, true);
    }

    function testSetDaoAuthFailed() public {
        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.setDaoAddress(address(10));
    }

    function testSetDaoVaultAuthFailed() public {
        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.setDaoVaultAddress(address(10));
    }

    function testSetRegistrationFeeAuthFailed() public {
        vm.expectRevert("PERMISSION_DENIED");
        operatorRegistry.setRegistrationFee(0.2 ether);
    }

    function testSetRegistrationFee() public {
        vm.prank(_dao);
        operatorRegistry.setRegistrationFee(0.2 ether);
        assertEq(operatorRegistry.registrationFee(), 0.2 ether);
    }

    function testSetDao() public {
        vm.prank(_dao);
        operatorRegistry.setDaoAddress(address(10));
        assertEq(operatorRegistry.dao(), address(10));
    }

    function testSetDaoVaultAddress() public {
        vm.prank(_dao);
        operatorRegistry.setDaoVaultAddress(address(10));
        assertEq(operatorRegistry.daoVaultAddress(), address(10));
    }
}
