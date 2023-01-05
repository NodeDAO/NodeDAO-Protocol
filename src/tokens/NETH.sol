// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract NETH is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ERC20Upgradeable
{
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // Calculate the amount of ETH backing an amount of nETH
    function getEthValue(uint256 _nethAmount) public view returns (uint256) {
        // TODO: get total eth balance
        uint256 totalPooledEth = 10;
        uint256 nEthSupply = totalSupply();

        // Use 1:1 ratio if no nETH is minted
        if (nEthSupply == 0) { return _nethAmount; }

        // Calculate and return
        return _nethAmount *  totalPooledEth / (nEthSupply);
    }

    // Calculate the amount of nETH backing an amount of ETH
    function getNethValue(uint256 _ethAmount) public view returns (uint256) {
        uint256 totalPooledEth = 10;
        uint256 nEthSupply = totalSupply();

        // Use 1:1 ratio if no nETH is minted
        if (nEthSupply == 0) { return _ethAmount; }

        require(totalPooledEth > 0, "Cannot calculate nETH token amount while total network balance is zero");

        // Calculate and return
        return _ethAmount * nEthSupply/ totalPooledEth;
    }

    // Mint nETH
    function mint(uint256 _ethAmount, address _to) internal returns (uint256) {
        // Get nETH amount
        uint256 nethAmount = getNethValue(_ethAmount);

        // Check nETH amount
        require(nethAmount > 0, "Invalid token mint amount");

        // Update balance & supply
        _mint(_to, nethAmount);

        // TODO: Emit tokens minted event
        // emit TokensMinted(_to, nethAmount, _ethAmount, block.timestamp);
        return nethAmount;
    }

    // Burn nETH for ETH
    function burn(uint256 _nethAmount) external {
        // Check nETH amount
        require(_nethAmount > 0, "Invalid token burn amount");
        require(balanceOf(msg.sender) >= _nethAmount, "Insufficient nETH balance");

        // Get ETH amount
        uint256 ethAmount = getEthValue(_nethAmount);

        // Get & check ETH balance
        // TODO: getTotalCollateral()
        uint256 ethBalance = 10;

        require(ethBalance >= ethAmount, "Insufficient ETH balance for exchange");

        // Update balance & supply
        _burn(msg.sender, _nethAmount);

        // TODO: Withdraw ETH from deposit pool if required
        // withdrawDepositCollateral(ethAmount);

        // UNSURE: Transfer ETH to sender
        // payable(msg.sender).transfer(ethAmount);
        // Emit tokens burned event
        // TODO: emit TokensBurned(msg.sender, _nethAmount, ethAmount, block.timestamp);
    }
}
