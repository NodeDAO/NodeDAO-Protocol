// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "ERC721A-Upgradeable/extensions/ERC721AQueryableUpgradeable.sol";

contract NFT is
    Initializable,
    OwnableUpgradeable,
    ERC721AQueryableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize() public initializer initializerERC721A {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __ERC721A_init("Validator Nft", "vNFT");
    }
}
