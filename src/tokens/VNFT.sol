// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "lib/ERC721A-Upgradeable/contracts/ERC721AUpgradeable.sol";
import "src/interfaces/ILiquidStaking.sol";

contract VNFT is
    Initializable,
    OwnableUpgradeable,
    ERC721AUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
  address public liquidStakingAddress;

  address constant public OPENSEA_PROXY_ADDRESS = 0x1E0049783F008A0085193E00003D00cd54003c71; // todo 0x1E0049783F008A0085193E00003D00cd54003c71 ?
  uint256 constant public MAX_SUPPLY = 6942069420;

  mapping(bytes => uint256) public validatorRecords; // operator_id
  mapping(uint256 => address) public lastOwners;

  bytes[] public _validators;

  uint256[] public _initHeights;

  bool private _isOpenSeaProxyActive = false;

  event BaseURIChanged(string _before, string _after);
  event Transferred(address _to, uint256 _amount);
  event LiquidStakingChanged(address _before, address _after);
  event OpenSeaState(bool _isActive);

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function initialize() public initializer initializerERC721A {
      __Ownable_init();
      __UUPSUpgradeable_init();
      __ReentrancyGuard_init();
      __ERC721A_init("Validator Nft", "vNFT");
  }

  modifier onlyLiquidStaking() {
    require(liquidStakingAddress == msg.sender, "Not allowed to mint/burn nft");
    _;
  }

  /**
   * @notice Returns the validators that are active (may contain validator that are yet active on beacon chain)
   */
  function activeValidators() external view returns (bytes[] memory) {
    uint256 total = _nextTokenId();
    uint256 tokenIdsIdx;
    bytes[] memory validators = new bytes[](total);
    TokenOwnership memory ownership;

    for (uint256 i = _startTokenId(); i < total; ++i) {
        ownership = _ownershipAt(i);
        if (ownership.burned) { 
          continue;
        }

        validators[tokenIdsIdx++] = _validators[i];
    }

    return validators;
  }

  /**
   * @notice Checks if a validator exists
   * @param pubkey - A 48 bytes representing the validator's public key
   */
  function validatorExists(bytes calldata pubkey) external view returns (bool) {
    return validatorRecords[pubkey] != 0; // operator 从1开始
  }

  /**
   * @notice Finds the validator's public key of a nft
   * @param tokenId - tokenId of the validator nft
   */
  function validatorOf(uint256 tokenId) external view returns (bytes memory) {
    return _validators[tokenId];
  }

  function operatorOf(uint256 tokenId) external view returns (uint256) {
    bytes memory _pubkey =  _validators[tokenId];
    return validatorRecords[_pubkey];
  }

  /**
   * @notice Finds all the validator's public key of a particular address
   * @param owner - The particular address
   */
  function validatorsOfOwner(address owner) public view returns (bytes[] memory) {
    unchecked {
      //slither-disable-next-line uninitialized-local
      uint256 tokenIdsIdx;
      //slither-disable-next-line uninitialized-local
      address currOwnershipAddr;
      uint256 tokenIdsLength = balanceOf(owner);
      bytes[] memory tokenIds = new bytes[](tokenIdsLength);
      TokenOwnership memory ownership;
      for (uint256 i = 0 ; tokenIdsIdx != tokenIdsLength; ++i) {
          ownership = _ownershipAt(i);
          if (ownership.burned) {
              continue;
          }
          if (ownership.addr != address(0)) {
              currOwnershipAddr = ownership.addr;
          }
          if (currOwnershipAddr == owner) {
              tokenIds[tokenIdsIdx++] = _validators[i];
          }
      }
      return tokenIds;
    }
  }

  /**
   * @notice Finds the tokenId of a validator
   * @dev Returns MAX_SUPPLY if not found
   * @param pubkey - A 48 bytes representing the validator's public key
   */ 
  function tokenOfValidator(bytes calldata pubkey) external view returns (uint256) {
    for (uint256 i = 0; i < _validators.length; i++) {
      if (keccak256(_validators[i]) == keccak256(pubkey) && _exists(i)) {
        return i;
      }
    }
    return MAX_SUPPLY;
  }

  /**
   * @notice Finds all the validator's public key of a particular operator
   * @param _operatorId - The particular address of the operator
   */
  function validatorsOfOperator(uint256 _operatorId) external view returns (bytes[] memory) {
    uint256 total = _nextTokenId();
    uint256 tokenIdsIdx;
    bytes[] memory validators = new bytes[](total);
    TokenOwnership memory ownership;

    for (uint256 i = _startTokenId(); i < total; ++i) {
        ownership = _ownershipAt(i);
        if (ownership.burned) { 
          continue;
        }
        if (validatorRecords[_validators[i]] == _operatorId) {
          validators[tokenIdsIdx++] = _validators[i];
        }
    }

    return validators;
  }


  /**
   * @notice Returns the init height of the tokenId
   * @param tokenId - tokenId of the validator nft
   */
  function initHeightOf(uint256 tokenId) external view returns (uint256) {
    require(_exists(tokenId), "Token does not exist");

    return _initHeights[tokenId];
  }

  /**
   * @notice Returns the last owner before the nft is burned
   * @param tokenId - tokenId of the validator nft
   */
  function lastOwnerOf(uint256 tokenId) external view returns (address) {
    require(_ownershipAt(tokenId).burned, "Token not burned yet");
    
    return lastOwners[tokenId];
  }

  function getLatestTokenId() external view returns (uint256) {
    return _nextTokenId();
  }

  /**
   * @notice Mints a Validator nft (vNFT)
   * @param _pubkey -  A 48 bytes representing the validator's public key
   * @param _to - The recipient of the nft
   * @param _operator - The operator repsonsible for operating the physical node
   */
  function whiteListMint(bytes calldata _pubkey, address _to, uint256 _operator) external onlyLiquidStaking {
    require(
      totalSupply() + 1 <= MAX_SUPPLY,
      "not enough remaining reserved for auction to support desired mint amount"
    );
    require(validatorRecords[_pubkey] == 0, "Pub key already in used");

    validatorRecords[_pubkey] = _operator;
    _validators.push(_pubkey);
    _initHeights.push(block.number);

    _safeMint(_to, 1);
  }

  /**
   * @notice Burns a Validator nft (vNFT)
   * @param tokenId - tokenId of the validator nft
   */
  function whiteListBurn(uint256 tokenId) external onlyLiquidStaking {
    lastOwners[tokenId] = ownerOf(tokenId);
    _burn(tokenId);
  }

  // // metadata URI
  string private _baseTokenURI;

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseTokenURI;
  }

  function setBaseURI(string calldata baseURI) external onlyOwner {
    emit BaseURIChanged(_baseTokenURI, baseURI);
    _baseTokenURI = baseURI;
  }

  function setLiquidStaking(address _liqStakingAddress) external onlyOwner {
    require(_liqStakingAddress != address(0), "LiquidStaking address provided invalid");
    emit LiquidStakingChanged(liquidStakingAddress, _liqStakingAddress);
    liquidStakingAddress = _liqStakingAddress;
  }

  // function to disable gasless listings for security in case
  // opensea ever shuts down or is compromised
  function setIsOpenSeaProxyActive(bool isOpenSeaProxyActive_)
      external
      onlyOwner
  {
    emit OpenSeaState(isOpenSeaProxyActive_);
    _isOpenSeaProxyActive = isOpenSeaProxyActive_;
  }

  function numberMinted(address owner) external view returns (uint256) {
    return _numberMinted(owner);
  }

  ////////below is the new code//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  function isApprovedForAll(address owner, address operator)
      public
      view
      override
      returns (bool)
  {
      // Get a reference to OpenSea's proxy registry contract by instantiating
      // the contract using the already existing address.

      if (
          _isOpenSeaProxyActive &&
          OPENSEA_PROXY_ADDRESS == operator
      ) {
          return true;
      }
      // if (operator == _liquidStakingAddress) {
      //     return true;
      // }

      return super.isApprovedForAll(owner, operator);
  }
}
