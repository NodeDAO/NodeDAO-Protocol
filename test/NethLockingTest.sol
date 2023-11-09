// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/neth/nethLocking.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "src/tokens/NETH.sol";

contract NethLockingTest is Test {
    NethLocking nethLockingImpl;
    NethLocking nethLocking;
    NETH neth;

    address _dao = address(1);
    address _user1 = address(2);
    address _user2 = address(3);

    function setUp() public {
        neth = new NETH();
        neth.setLiquidStaking(_dao);
        vm.prank(_dao);
        neth.whiteListMint(100000 ether, _user1);
        vm.prank(_dao);
        neth.whiteListMint(200000 ether, _user2);

        nethLockingImpl = new NethLocking();
        bytes memory _data;
        ERC1967Proxy proxyAddr = new ERC1967Proxy(address(nethLockingImpl), _data);
        nethLocking = NethLocking(address(proxyAddr));
        nethLocking.initialize(_dao);

        vm.prank(_user1);
        neth.approve(address(nethLocking), type(uint256).max);
        vm.prank(_user2);
        neth.approve(address(nethLocking), type(uint256).max);

        vm.prank(_dao);
        nethLocking.setNethContractAddress(address(neth));
        vm.prank(_dao);
        nethLocking.unpause();
    }

    function testFailInitialize() public {
        nethLockingImpl.initialize(_dao);
    }

    function testNethLocking() public {
        vm.roll(1);

        vm.prank(_user1);
        nethLocking.depositNeth(20000 ether);

        vm.roll(100000);
        (uint256 _balance, uint256 _credits) = nethLocking.getUserLockingInfo(_user1);
        assertEq(_balance, 20000 ether);
        assertEq(_credits, 20000 ether * (100000 - 1));

        vm.prank(_user2);
        nethLocking.depositNeth(50000 ether);

        vm.roll(200000);
        (uint256 _balance2, uint256 _credits2) = nethLocking.getUserLockingInfo(_user2);
        assertEq(_balance2, 50000 ether);
        assertEq(_credits2, 50000 ether * (200000 - 100000));

        vm.roll(500000);
        (_balance, _credits) = nethLocking.getUserLockingInfo(_user1);
        assertEq(_balance, 20000 ether);
        assertEq(_credits, 20000 ether * (500000 - 1));
        (_balance2, _credits2) = nethLocking.getUserLockingInfo(_user2);
        assertEq(_balance2, 50000 ether);
        assertEq(_credits2, 50000 ether * (500000 - 100000));

        vm.prank(_user1);
        nethLocking.depositNeth(30000 ether);
        (_balance, _credits) = nethLocking.getUserLockingInfo(_user1);
        assertEq(_balance, 50000 ether);
        assertEq(_credits, 20000 ether * (500000 - 1));

        vm.roll(600000);
        vm.prank(_user1);
        nethLocking.withdrawNeth(30000 ether);
        (_balance, _credits) = nethLocking.getUserLockingInfo(_user1);
        assertEq(_balance, 20000 ether);
        assertEq(_credits, 20000 ether * (500000 - 1) + 50000 ether * (600000 - 500000));
        assertEq(neth.balanceOf(_user1), 80000 ether);
    }

    function testFailWithdrawNeth() public {
        vm.prank(_user1);
        nethLocking.withdrawNeth(30000 ether);
    }
}
