// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/registries/NodeOperatorRegistry.sol";

contract NodeOperatorRegistryTest is Test {
    event NodeOperatorRegistered(uint256 id, string name, address rewardAddress, address controllerAddress);
    event NodeOperatorTrustedSet(uint256 id, string name, bool trusted);
    event NodeOperatorTrustedRemove(uint256 id, string name, bool trusted);
    event NodeOperatorNameSet(uint256 id, string name);
    event NodeOperatorRewardAddressSet(uint256 id, string name, address rewardAddress);
    event NodeOperatorControllerAddressSet(uint256 id, string name, address controllerAddress);
    event Transferred(address _to, uint256 _amount);

    NodeOperatorRegistry operatorRegistry;
    address _dao = address(1);
    address _daoValutAddress = address(2);

    function initializer() private {
        operatorRegistry.initialize(_dao, _daoValutAddress);
    }

    function checkOperator(bool _trusted, string memory _name, address _rewardAddress, address _controllerAddress) public {
        bool trusted;
        string memory name;
        address rewardAddress;
        address controllerAddress;
        address valutContractAddress; // todo
        (trusted, name, rewardAddress, controllerAddress, valutContractAddress) = operatorRegistry.getNodeOperator(0, true);
        assertEq(trusted, _trusted);
        assertEq(name, _name);
        assertEq(rewardAddress, _rewardAddress);
        assertEq(controllerAddress, _controllerAddress);
    }

    function setUp() public {
        operatorRegistry = new NodeOperatorRegistry();
        initializer();
    }

    function testDao() public {
        assertEq(operatorRegistry.dao(), _dao);
        assertEq(operatorRegistry.daoValutAddress(), _daoValutAddress);
    }

    // -------------

    function testFailRegisterOperator() public {
        operatorRegistry.registerOperator{value: 0.09 ether}("one", address(3), address(4), address(5));
    }

    function testRegisterOperator() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
    }

    function testRegisterOperatorMoreValue() public {
        vm.expectEmit(true, true, false, true);
        emit Transferred(_daoValutAddress, 0.1 ether);
        emit Transferred(msg.sender, 0.11 ether);
        operatorRegistry.registerOperator{value: 0.21 ether}("one", address(3), address(4), address(5));
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
        emit NodeOperatorRegistered(0, "one", address(3), address(4));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorTrustedSet(0, "one", true);

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(0);

        checkOperator(true, "one", address(3), address(4));
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
        emit NodeOperatorRegistered(0, "one", address(3), address(4));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorTrustedRemove(0, "one", false);
        
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(_dao);
        operatorRegistry.removeTrustedOperator(0);

        checkOperator(false, "one", address(3), address(4));
    }

    // -------------

    function testSetNodeOperatorNameAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setNodeOperatorName(0, "two");
    }

    function testSetNodeOperatorNameNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorName(0, "two");
    }

    function testSetNodeOperatorName() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(0, "one", address(3), address(4));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorNameSet(0, "two");

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorName(0, "two");
        
        checkOperator(false, "two", address(3), address(4));
    }

    // -------------

    function testSetNodeOperatorRewardAddressAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setNodeOperatorRewardAddress(0, address(5));
    }

    function testSetNodeOperatorRewardAddressNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorRewardAddress(0, address(5));
    }

    function testSetNodeOperatorRewardAddressName() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(0, "one", address(3), address(4));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorNameSet(0, "two");

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorRewardAddress(0, address(5));
        
        checkOperator(false, "one", address(5), address(4));
    }

    // -------------

    function testSetNodeOperatorControllerAddressAuthFailed() public {
        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));

        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setNodeOperatorControllerAddress(0, address(5));
    }

    function testSetNodeOperatorControllerAddressNotExist() public {
        vm.expectRevert("NODE_OPERATOR_NOT_FOUND");
        operatorRegistry.setNodeOperatorControllerAddress(0, address(5));
    }

    function testSetNodeOperatorControllerAddressName() public {
        vm.expectEmit(true, true, false, true);
        emit NodeOperatorRegistered(0, "one", address(3), address(4));
        emit Transferred(address(1), 0.1 ether);
        emit NodeOperatorNameSet(0, "two");

        operatorRegistry.registerOperator{value: 0.1 ether}("one", address(3), address(4), address(5));
        vm.prank(address(4));
        operatorRegistry.setNodeOperatorControllerAddress(0, address(5));
        
        checkOperator(false, "one", address(3), address(5));
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
        
        bool trused = operatorRegistry.isTrustedOperator(0);
        assertEq(trused, false);

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(0);

        trused = operatorRegistry.isTrustedOperator(0);
        assertEq(trused, true);
    }

    function testSetDaoAuthFailed() public {
         vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setDaoAddress(address(10));
    }

    function testSetDaoValutAuthFailed() public {
        vm.expectRevert("AUTH_FAILED");
        operatorRegistry.setDaoValutAddress(address(10));
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

    function testSetDaoValutAddress() public {
        vm.prank(_dao);
        operatorRegistry.setDaoValutAddress(address(10));
        assertEq(operatorRegistry.daoValutAddress(), address(10));
    }

}
