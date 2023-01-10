// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "src/interfaces/INEth.sol";
import "src/interfaces/ILiquidStaking.sol";

contract NETH is Initializable, OwnableUpgradeable, UUPSUpgradeable, ERC20Upgradeable, INEth {
    event TokensMinted(address indexed to, uint256 amount, uint256 ethAmount, uint256 time);
    event TokensBurned(address indexed from, uint256 amount, uint256 ethAmount, uint256 time);
    event EtherDeposited(address indexed from, uint256 amount, uint256 time);

    ILiquidStaking iLiqStaking;

    function initialize(address _liqStakingAddress) external initializer {
        iLiqStaking = ILiquidStaking(_liqStakingAddress);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // Calculate the amount of ETH backing an amount of nETH
    function getEthValue(uint256 _nethAmount) public payable override returns (uint256) {
        uint256 totalPooledEth = iLiqStaking.getTotalPooledEther();
        uint256 nEthSupply = totalSupply();

        // Use 1:1 ratio if no nETH is minted
        if (nEthSupply == 0) return _nethAmount;

        // Calculate and return
        return _nethAmount * (totalPooledEth / nEthSupply);
    }

    // Calculate the amount of nETH backing an amount of ETH
    function getNethValue(uint256 _ethAmount) public payable override returns (uint256) {
        uint256 totalPooledEth = iLiqStaking.getTotalPooledEther();
        uint256 nEthSupply = totalSupply();

        // Use 1:1 ratio if no nETH is minted
        if (nEthSupply == 0) return _ethAmount;

        require(totalPooledEth > 0, "Cannot calculate nETH token amount while total network balance is zero");

        // Calculate and return
        return _ethAmount * nEthSupply / totalPooledEth;
    }

    // Mint nETH
    function mint(uint256 _ethAmount, address _to) external override returns (uint256) {
        // Get nETH amount
        uint256 nethAmount = getNethValue(_ethAmount);

        // Check nETH amount
        require(nethAmount > 0, "Invalid token mint amount");

        // Update balance & supply
        _mint(_to, nethAmount);

        // TODO: Emit tokens minted event
        emit TokensMinted(_to, nethAmount, _ethAmount, block.timestamp);
        return nethAmount;
    }

    // Burn nETH for ETH
    function burn(uint256 _nethAmount) external override returns (uint256) {
        // Check nETH amount
        require(_nethAmount > 0, "Invalid token burn amount");
        require(balanceOf(msg.sender) >= _nethAmount, "Insufficient nETH balance");

        // Get ETH amount
        uint256 ethAmount = getEthValue(_nethAmount);

        // Update balance & supply
        _burn(msg.sender, _nethAmount);

        // Emit tokens burned event
        emit TokensBurned(msg.sender, _nethAmount, ethAmount, block.timestamp);

        return ethAmount;
    }

    // Receive an ETH deposit from a generous individual
    receive() external payable {
        // Emit ether deposited event
        emit EtherDeposited(msg.sender, msg.value, block.timestamp);
    }
}
