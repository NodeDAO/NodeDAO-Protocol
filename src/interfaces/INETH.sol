// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.8;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title Interface for NETH
 */
interface INETH is IERC20 {
    /**
     * @notice mint nETHH
     * @param amount mint amount
     * @param account mint account
     */
    function whiteListMint(uint256 amount, address account) external;

    /**
     * @notice burn nETHH
     * @param amount burn amount
     * @param account burn account
     */
    function whiteListBurn(uint256 amount, address account) external;
}
