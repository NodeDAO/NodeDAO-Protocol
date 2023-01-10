// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/tokens/VNFT.sol";

contract VNFTTest is Test {
    VNFT vnft;
    function setUp() public {
        vnft = new VNFT();
        vnft.initialize();
    }

    function testSetLiquidStaking() public {
        vnft.setLiquidStaking(address(1));
        assertEq(address(1), vnft.liquidStakingAddress());
    }

    function testFailSetLiquidStaking() public {
        vm.prank(address(0));
        vnft.setLiquidStaking(address(1));
        assertEq(address(1), vnft.liquidStakingAddress());
    }

    function testWhiteListMint() public {
        vnft.setLiquidStaking(address(1));
        vm.prank(address(1));
        vnft.whiteListMint(bytes("1"), address(2), 1);
    }

    function testFailWhiteListMint() public {
        vnft.setLiquidStaking(address(1));
        vnft.whiteListMint(bytes("1"), address(2), 1);
        assertEq(1, vnft.balanceOf(address(2)));
    }

    function testWhiteListBurn() public {
        vnft.setLiquidStaking(address(1));
        vm.prank(address(1));
        vnft.whiteListMint(bytes("1"), address(2), 1);
        assertEq(1, vnft.balanceOf(address(2)));

        vm.prank(address(1));
        vnft.whiteListBurn(0);
        assertEq(0, vnft.balanceOf(address(2)));
    }

    function testFailWhiteListBurn() public {
        vnft.setLiquidStaking(address(1));
        vm.prank(address(1));
         vnft.whiteListMint(bytes("1"), address(2), 1);
        assertEq(1, vnft.balanceOf(address(2)));

        vnft.whiteListBurn(0);
    }
}