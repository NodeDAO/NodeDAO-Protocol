// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "src/tokens/VNFT.sol";
import "forge-std/console.sol";

contract VNFTTest is Test {
    VNFT vnft;

    function setUp() public {
        vnft = new VNFT();
        vnft.initialize();
    }

    function testSetLiquidStaking() public {
        vnft.setLiquidStaking(address(1));
        assertEq(address(1), vnft.liquidStakingContractAddress());
    }

    function testFailSetLiquidStaking() public {
        vm.prank(address(0));
        vnft.setLiquidStaking(address(1));
        assertEq(address(1), vnft.liquidStakingContractAddress());
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

    function testGetLatestTokenId() public {
        vnft.setLiquidStaking(address(1));
        vm.prank(address(1));
        vnft.whiteListMint(bytes("1"), address(2), 1);
        vnft.initHeightOf(0);
    }

    function testWhiteListMintEmpty() public {
        vnft.setLiquidStaking(address(1));
        vm.startPrank(address(1));

        vnft.whiteListMint(bytes("1"), address(2), 1);
        assertEq(vnft.validatorOf(0), bytes("1"));

        vnft.whiteListMint(bytes(""), address(2), 1);
        assertEq(vnft.validatorOf(1), bytes(""));
        assertEq(vnft.operatorEmptyNfts(1, 0), 1);
        assertEq(vnft.operatorEmptyNftIndex(1), 0);

        vnft.whiteListMint(bytes("2"), address(2), 1);
        assertEq(vnft.operatorEmptyNfts(1, 0), 1);
        assertEq(vnft.operatorEmptyNftIndex(1), 1);
        assertEq(vnft.validatorOf(1), bytes("2"));

        vnft.whiteListMint(bytes("3"), address(2), 1);
        assertEq(vnft.operatorEmptyNfts(1, 0), 1);
        assertEq(vnft.operatorEmptyNftIndex(1), 1);
        assertEq(vnft.validatorOf(2), bytes("3"));
        assertEq(3, vnft.balanceOf(address(2)));
    }

    function testActiveValidators() public {
        vnft.setLiquidStaking(address(1));
        vm.startPrank(address(1));

        uint256 tokenId0 = vnft.whiteListMint(bytes("1"), address(2), 1);
        assertEq(vnft.validatorOf(0), bytes("1"));
        assertEq(vnft.activeValidators().length, 1);
        uint256 tokenId1 = vnft.whiteListMint(bytes(""), address(2), 1);
        assertEq(vnft.activeValidators().length, 1);
        assertEq(vnft.activeValidators().length, vnft.activeNfts().length);
        uint256 tokenId2 = vnft.whiteListMint(bytes("2"), address(2), 2);
        assertEq(vnft.activeValidators()[0], bytes("1"));
        assertEq(vnft.activeValidators()[1], bytes("2"));
        assertEq(vnft.activeValidators().length, 2);
        assertEq(vnft.activeValidators().length, vnft.activeNfts().length);
        assertEq(0, tokenId0);
        assertEq(1, tokenId1);
        assertEq(2, tokenId2);
        assertEq(0, vnft.activeNfts()[0]);
        assertEq(2, vnft.activeNfts()[1]);

        assertEq(vnft.getEmptyNftCounts(), 1);
        uint256 tokenId3 = vnft.whiteListMint(bytes("3"), address(2), 1);
        assertEq(tokenId3, tokenId1);
        assertEq(vnft.getEmptyNftCounts(), 0);
        assertEq(vnft.activeValidators()[0], bytes("1"));
        assertEq(vnft.activeValidators()[1], bytes("3"));
        assertEq(vnft.activeValidators()[2], bytes("2"));
        assertEq(0, vnft.activeNfts()[0]);
        assertEq(1, vnft.activeNfts()[1]);
        assertEq(2, vnft.activeNfts()[2]);
        assertEq(vnft.totalSupply(), 3);

        assertEq(vnft.validatorExists(bytes("3")), true);

        vnft.whiteListBurn(1);
        assertEq(vnft.totalSupply(), 2);
        assertEq(vnft.lastOwnerOf(1), address(2));
        assertEq(vnft.getNftCountsOfOperator(1), 1);
        assertEq(vnft.getNftCountsOfOperator(2), 1);

        vm.stopPrank();

        vnft.setBaseURI("/test/");
        assertEq(vnft.tokenURI(0), "/test/0");
    }
}
