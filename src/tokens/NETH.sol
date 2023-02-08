// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "src/interfaces/INETH.sol";

/**
 * @title NodeDao nETH Contract
 */
contract NETH is INETH, ERC20, Ownable {
    address public liquidStakingContractAddress;

    event LiquidStakingContractSet(address liquidStakingContractAddress, address _liquidStaking);

    modifier onlyLiquidStaking() {
        require(liquidStakingContractAddress == msg.sender, "Not allowed to touch funds");
        _;
    }

    constructor() ERC20("Node ETH", "nETH") {}

    /**
     * @notice set LiquidStaking contract address
     * @param _liquidStaking liquidStaking address
     */
    function setLiquidStaking(address _liquidStaking) public onlyOwner {
        emit LiquidStakingContractSet(liquidStakingContractAddress, _liquidStaking);
        liquidStakingContractAddress = _liquidStaking;
    }

    /**
     * @notice mint nETHH
     * @param amount mint amount
     * @param account mint account
     */
    function whiteListMint(uint256 amount, address account) external onlyLiquidStaking {
        _mint(account, amount);
    }

    /**
     * @notice burn nETHH
     * @param amount burn amount
     * @param account burn account
     */
    function whiteListBurn(uint256 amount, address account) external onlyLiquidStaking {
        _burn(account, amount);
    }
}
