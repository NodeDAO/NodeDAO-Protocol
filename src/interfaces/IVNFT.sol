// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "lib/ERC721A-Upgradeable/contracts/IERC721AUpgradeable.sol";

interface IVNFT is IERC721AUpgradeable {
    function activeNfts() external view returns (uint256[] memory);

    /**
     * @notice Returns the validators that are active (may contain validator that are yet active on beacon chain)
     */
    function activeValidators() external view returns (bytes[] memory);

    /**
     * @notice Checks if a validator exists
     * @param pubkey - A 48 bytes representing the validator's public key
     */
    function validatorExists(bytes calldata pubkey) external view returns (bool);

    /**
     * @notice Finds the validator's public key of a nft
     * @param tokenId - tokenId of the validator nft
     */
    function validatorOf(uint256 tokenId) external view returns (bytes memory);

    /**
     * @notice Finds all the validator's public key of a particular address
     * @param owner - The particular address
     */
    function validatorsOfOwner(address owner) external view returns (bytes[] memory);

    /**
     * @notice Finds the operator id of a nft
     * @param tokenId - tokenId of the validator nft
     */
    function operatorOf(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Get the number of operator's nft
     * @param operatorId - operator id
     */
    function getNftCountsOfOperator(uint256 operatorId) external view returns (uint256);

    /**
     * @notice Finds the tokenId of a validator
     * @dev Returns MAX_SUPPLY if not found
     * @param pubkey - A 48 bytes representing the validator's public key
     */
    function tokenOfValidator(bytes calldata pubkey) external view returns (uint256);

    /**
     * @notice Returns the last owner before the nft is burned
     * @param tokenId - tokenId of the validator nft
     */
    function lastOwnerOf(uint256 tokenId) external view returns (address);

    /**
     * @notice Mints a Validator nft (vNFT)
     * @param _pubkey -  A 48 bytes representing the validator's public key
     * @param _to - The recipient of the nft
     * @param _operatorId - The operator repsonsible for operating the physical node
     */
    function whiteListMint(bytes calldata _pubkey, address _to, uint256 _operatorId) external returns (bool, uint256);

    /**
     * @notice Burns a Validator nft (vNFT)
     * @param tokenId - tokenId of the validator nft
     */
    function whiteListBurn(uint256 tokenId) external;
}
