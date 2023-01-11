// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/registries/NodeOperatorRegistry.sol";

contract NodeOperatorRegistryTest is Test {
    event NodeOperatorRegistered(uint256 id, string name, address rewardAddress, address controllerAddress, address _vaultContractAddress);
    event NodeOperatorTrustedSet(uint256 id, string name, bool trusted);
    event NodeOperatorTrustedRemove(uint256 id, string name, bool trusted);
    event NodeOperatorNameSet(uint256 id, string name);
    event NodeOperatorRewardAddressSet(uint256 id, string name, address rewardAddress);
    event NodeOperatorControllerAddressSet(uint256 id, string name, address controllerAddress);
    event Transferred(address _to, uint256 _amount);

    NodeOperatorRegistry operatorRegistry;
    address _dao = address(1);
    address _daoVaultAddress = address(2);

    function initializer() private {
        operatorRegistry.initialize(_dao, _daoVaultAddress);
    }

    function checkOperator(bool _trusted, string memory _name, address _rewardAddress, address _controllerAddress, address _vaultContractAddress) public {
        bool trusted;
        string memory name;
        address rewardAddress;
        address controllerAddress;
        address vaultContractAddress;
        (trusted, name, rewardAddress, controllerAddress, vaultContractAddress) = operatorRegistry.getNodeOperator(1, true);
        assertEq(trusted, _trusted);
        assertEq(name, _name);
        assertEq(rewardAddress, _rewardAddress);
        assertEq(controllerAddress, _controllerAddress);
        assertEq(vaultContractAddress, _vaultContractAddress);
    }

    function setUp() public {
        operatorRegistry = new NodeOperatorRegistry();
        initializer();
    }

    function testDao() public {
        assertEq(operatorRegistry.dao(), _dao);
        assertEq(operatorRegistry.daoVaultAddress(), _daoVaultAddress);
    }

    // -------------

    function testFailRegisterOperator() public {
        operatorRegistry.registerOperator{value: 0.09 ether}("one", address(3), address(4), address(5));
    }

    function testRegisterOperator() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
    }

    function testRegisterOperatorMoreValue() public {
        vm.expectEmit(true, true, false, true);
        emit Transferred(_daoVaultAddress, 0.1 ether);
        emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
    }

    // -------------

    function testSetTrustedOperatorAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setTrustedOperator(0);
    }

    function testSetTrustedOperatorNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(0);
    }

    function testSetTrustedOperator() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorTrustedSet(1, "one", true);

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        checkOperator(true, "one", address(3), address(4), address(5));
    }

    // -------------

    function testRemoveTrustedOperatorAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.removeTrustedOperator(0);
    }

    function testRemoveTrustedOperatorNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        vm.prank(_dao);
        operatorRegistry.removeTrustedOperator(0);
    }

    function testRemoveTrustedOperator() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorTrustedSet(1, "one", true);
        emit NodeOperatorTrustedRemove(1, "one", false);
        
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);
        vm.prank(_dao);
        operatorRegistry.removeTrustedOperator(1);

        checkOperator(false, "one", address(3), address(4), address(5));
    }

    // -------------

    function testSetNodeOperatorNameAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setNodeOperatorName(1, "two");
    }

    function testSetNodeOperatorNameNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorName(1, "two");
    }

    function testSetNodeOperatorName() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorNameSet(1, "two");

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorName(1, "two");
        
        checkOperator(false, "two", address(3), address(4), address(5));
    }

    // -------------

    function testSetNodeOperatorRewardAddressAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setNodeOperatorRewardAddress(1, address(5));
    }

    function testSetNodeOperatorRewardAddressNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorRewardAddress(1, address(5));
    }

    function testSetNodeOperatorRewardAddressName() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorNameSet(0, "two");

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorRewardAddress(1, address(5));
        
        checkOperator(false, "one", address(5), address(4), address(5));
    }

    // -------------

    function testSetNodeOperatorControllerAddressAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setNodeOperatorControllerAddress(1, address(5));
    }

    function testSetNodeOperatorControllerAddressNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorControllerAddress(1, address(5));
    }

    function testSetNodeOperatorControllerAddressName() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(1, "one", address(3), address(4), address(5));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorNameSet(1, "two");

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorControllerAddress(1, address(5));
        
        checkOperator(false, "one", address(3), address(5), address(5));
    }

    function testGetNodeOperatorsCount() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        uint256 count = operatorRegistry.getNodeOperatorsCount();
        assertEq(count, 1);

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        count = operatorRegistry.getNodeOperatorsCount();
        assertEq(count, 4);
    }

    // -------------

    function testIsTrustedOperatorNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.isTrustedOperator(0);
    }

    function testTrustedOperator() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        
        bool trused = operatorRegistry.isTrustedOperator(1);
        assertEq(trused, false);

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        trused = operatorRegistry.isTrustedOperator(1);
        assertEq(trused, true);
    }

    function testSetDaoAuthFailed() public {
         vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setDaoAddress(address(10));
    }

    function testSetDaoVaultAuthFailed() public {
        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setDaoVaultAddress(address(10));
    }

    function testSetRegistrationFeeAuthFailed() public {
        vm.expectRevert("AUTH_FAILED");
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
