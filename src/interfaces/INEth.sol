// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

interface INEth {
    function getEthValue(uint256 _nethAmount) external payable returns (uint256);
    function getNethValue(uint256 _ethAmount) external payable returns (uint256);
    function mint(uint256 _ethAmount, address _to) external returns (uint256);
    function burn(uint256 _nethAmount) external returns (uint256);
}
