// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "lib/ERC721A-Upgradeable/contracts/IERC721AUpgradeable.sol";

interface IVNFT is IERC721AUpgradeable {
    function activeValidators() external view returns (bytes[] memory);

    function validatorExists(bytes calldata pubkey) external view returns (bool);

    function validatorOf(uint256 tokenId) external view returns (bytes memory);

    function validatorsOfOwner(address owner) external view returns (bytes[] memory);

    function operatorOf(uint256 tokenId) external view returns (uint256);

    function tokenOfValidator(bytes calldata pubkey) external view returns (uint256);

    function setGasHeight(uint256 tokenId, uint256 value) external;

    function gasHeightOf(uint256 tokenId) external view returns (uint256);

    function lastOwnerOf(uint256 tokenId) external view returns (address);

    function whiteListMint(bytes calldata data, address _to, uint256 _operatorId) external payable;

    function whiteListBurn(uint256 tokenId) external;

    function getLatestTokenId() external view returns (uint256);
}
