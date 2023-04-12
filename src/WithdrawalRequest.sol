// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/INETH.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/IVaultManager.sol";

contract WithdrawalRequest is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    ILiquidStaking public liquidStakingContract;
    IVNFT public vNFTContract;
    INETH public nETHContract;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    IVaultManager public vaultManagerContract;
    address public withdrawOracleContractAddress;
    address public dao;

    // key is tokenId, value is nft unstake blocknumber
    mapping(uint256 => uint256) internal nftUnstakeBlockNumbers;

    // key is operatorId, value is operator unstake tokenid lists
    mapping(uint256 => uint256[]) internal operatorUnstakeNftLists;

    // large withdrawals request
    uint256 public constant MIN_NETH_WITHDRAWAL_AMOUNT = 32 * 1e18;
    uint256 public constant MAX_NETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;

    // For large withdrawals, the withdrawn Neth will be locked in the liquid contract and wait for the user to claim to complete the burning
    uint256 public totalLockedNethBalance;
    // The total amount of requests for large withdrawals by the operator
    mapping(uint256 => uint256) public operatorPendingEthRequestAmount;
    // Repay the pool amount for large withdrawals
    mapping(uint256 => uint256) internal operatorPendingEthPoolBalance;

    struct WithdrawalInfo {
        uint256 operatorId;
        uint256 withdrawHeight;
        uint256 withdrawNethAmount;
        uint256 withdrawExchange;
        uint256 claimEthAmount;
        address owner;
        bool isClaim;
    }

    // For large withdrawal requests, it is allowed to claim out of queue order
    WithdrawalInfo[] internal withdrawalQueues;

    event NftUnstake(uint256 indexed _operatorId, uint256 tokenId);
    event LargeWithdrawalsRequest(uint256 _operatorId, address sender, uint256 totalNethAmount);
    event WithdrawalsReceive(uint256 _operatorId, uint256 _amount);

    modifier onlyLiquidStaking() {
        require(address(liquidStakingContract) == msg.sender, "PERMISSION_DENIED");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address _dao,
        address _liquidStakingAddress,
        address _nVNFTContractAddress,
        address _nETHContractAddress,
        address _nodeOperatorRegistryAddress,
        address _withdrawOracleContractAddress,
        address _vaultManagerContract
    ) public initializer {
        liquidStakingContract = ILiquidStaking(_liquidStakingAddress);
        vNFTContract = IVNFT(_nVNFTContractAddress);
        nETHContract = INETH(_nETHContractAddress);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryAddress);
        withdrawOracleContractAddress = _withdrawOracleContractAddress;
        vaultManagerContract = IVaultManager(_vaultManagerContract);
        dao = _dao;
    }

    /**
     * @notice Perform unstake operation on the held nft, an irreversible operation, and get back the pledged deth
     * @param _tokenIds unstake token id
     */
    function unstakeNFT(uint256[] calldata _tokenIds) external nonReentrant whenNotPaused {
        uint256[] memory operatorIds = new uint256[] (1);
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            require(nftUnstakeBlockNumbers[tokenId] == 0, "The tokenId already unstake");
            require(msg.sender == vNFTContract.ownerOf(tokenId), "The sender must be the nft owner");

            uint256 operatorId = vNFTContract.operatorOf(tokenId);
            operatorIds[0] = operatorId;
            vaultManagerContract.settleAndReinvestElReward(operatorIds);

            bytes memory pubkey = vNFTContract.validatorOf(tokenId);
            if (keccak256(pubkey) == keccak256(bytes(""))) {
                liquidStakingContract.fastUnstakeNFT(operatorId, tokenId, msg.sender);
            } else {
                nftUnstakeBlockNumbers[tokenId] = block.number;
                operatorUnstakeNftLists[operatorId].push(tokenId);
            }

            emit NftUnstake(operatorId, tokenId);
        }
    }

    /**
     * @notice Large withdrawal request, used for withdrawals over 32neth and less than 1000 neth.
     * @param _operatorId operator id
     * @param _amounts untake neth amount
     */
    function requestLargeWithdrawals(uint256 _operatorId, uint256[] calldata _amounts)
        public
        nonReentrant
        whenNotPaused
    {
        uint256 totalRequestNethAmount = 0;
        uint256 totalPendingEthAmount = 0;

        uint256 _exchange = liquidStakingContract.getEthOut(1 ether);
        for (uint256 i = 0; i < _amounts.length; ++i) {
            uint256 _amount = _amounts[i];
            require(
                _amount >= MIN_NETH_WITHDRAWAL_AMOUNT && _amount <= MAX_NETH_WITHDRAWAL_AMOUNT, "invalid request amount"
            );

            uint256 amountOut = liquidStakingContract.getEthOut(_amount);
            withdrawalQueues.push(
                WithdrawalInfo({
                    operatorId: _operatorId,
                    withdrawHeight: block.number,
                    withdrawNethAmount: _amount,
                    withdrawExchange: _exchange,
                    claimEthAmount: amountOut,
                    owner: msg.sender,
                    isClaim: false
                })
            );

            totalRequestNethAmount += _amount;
            totalPendingEthAmount += amountOut;
        }

        bool success = nETHContract.transferFrom(msg.sender, address(this), totalRequestNethAmount);
        require(success, "Failed to transfer neth");

        liquidStakingContract.largeWithdrawalUnstake(_operatorId, msg.sender, totalRequestNethAmount);
        totalLockedNethBalance += totalRequestNethAmount;
        operatorPendingEthRequestAmount[_operatorId] += totalPendingEthAmount;

        emit LargeWithdrawalsRequest(_operatorId, msg.sender, totalRequestNethAmount);
    }

    function claimLargeWithdrawals(uint256[] calldata requestIds) public nonReentrant whenNotPaused {
        uint256 totalRequestNethAmount = 0;
        uint256 totalPendingEthAmount = 0;

        for (uint256 i = 0; i < requestIds.length; ++i) {
            uint256 id = requestIds[i];
            WithdrawalInfo memory wInfo = withdrawalQueues[id];
            require(wInfo.owner == msg.sender, "no permission");
            require(!wInfo.isClaim, "requestId already claimed");
            withdrawalQueues[id].isClaim = true;
            totalRequestNethAmount += wInfo.withdrawNethAmount;
            totalPendingEthAmount += wInfo.claimEthAmount;
            operatorPendingEthRequestAmount[wInfo.operatorId] -= wInfo.claimEthAmount;
            operatorPendingEthPoolBalance[wInfo.operatorId] -= wInfo.claimEthAmount;
        }

        nETHContract.transferFrom(address(this), address(liquidStakingContract), totalRequestNethAmount);
        liquidStakingContract.largeWithdrawalBurnNeth(totalRequestNethAmount);
        totalLockedNethBalance -= totalRequestNethAmount;
        payable(msg.sender).transfer(totalPendingEthAmount);

        // todo emit
    }

    /**
     * @notice Get the tokenid set that the user initiates to exit but the operator has not yet operated
     * @param _operatorId operator Id
     */
    function getUserUnstakeButOperatorNoExitNfs(uint256 _operatorId) external view returns (uint256[] memory) {
        uint256 counts = 0;
        uint256[] memory tokenIds = operatorUnstakeNftLists[_operatorId];
        uint256[] memory exitBlockNumbers = vNFTContract.getNftExitBlockNumbers(tokenIds);
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            if (exitBlockNumbers[i] == 0) {
                counts += 1;
            }
        }

        uint256[] memory noExitNfts = new uint256[] (counts);
        uint256 j = 0;
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            if (exitBlockNumbers[i] == 0) {
                noExitNfts[j++] = i;
            }
        }

        return noExitNfts;
    }
    /**
     * @notice get nft unstake block number
     * @param _tokenId token id
     */

    function getNftUnstakeBlockNumber(uint256 _tokenId) public view returns (uint256) {
        return nftUnstakeBlockNumbers[_tokenId];
    }
    /**
     * @notice Obtain all large withdrawal requests of an operator
     * @param _operatorId operator Id
     */

    function getWithdrawalOfOperator(uint256 _operatorId) external view returns (WithdrawalInfo[] memory) {
        uint256 counts = 0;

        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].operatorId == _operatorId) {
                counts += 1;
            }
        }

        WithdrawalInfo[] memory wInfo = new WithdrawalInfo[](counts);
        uint256 wIndex = 0;
        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].operatorId == _operatorId) {
                wInfo[wIndex++] = withdrawalQueues[i];
            }
        }

        return wInfo;
    }
    /**
     * @notice Can get a large amount of active withdrawal requests from an address
     * @param _owner _owner address
     */

    function getWithdrawalRequestIdOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 counts = 0;
        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].owner == _owner && !withdrawalQueues[i].isClaim) {
                counts += 1;
            }
        }

        uint256[] memory ids = new uint256[](counts);
        uint256 index = 0;
        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].owner == _owner && !withdrawalQueues[i].isClaim) {
                ids[index++] = i;
            }
        }

        return ids;
    }

    function getNftUnstakeBlockNumbers(uint256 _tokenId) external view returns (uint256) {
        return nftUnstakeBlockNumbers[_tokenId];
    }

    function getOperatorLargeWitdrawalPendingInfo(uint256 _operatorId) external view returns (uint256, uint256) {
        return (operatorPendingEthRequestAmount[_operatorId], operatorPendingEthPoolBalance[_operatorId]);
    }

    function getWithdrawalOfRequestId(uint256 _requestId)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, address, bool)
    {
        require(_requestId < withdrawalQueues.length - 1, "invalid requestId");
        WithdrawalInfo memory wInfo = withdrawalQueues[_requestId];

        return (
            wInfo.operatorId,
            wInfo.withdrawHeight,
            wInfo.withdrawNethAmount,
            wInfo.withdrawExchange,
            wInfo.claimEthAmount,
            wInfo.owner,
            wInfo.isClaim
        );
    }

    function receiveWithdrawals(uint256 _operatorId, uint256 _amount) external payable onlyLiquidStaking {
        operatorPendingEthPoolBalance[_operatorId] += _amount;
        emit WithdrawalsReceive(_operatorId, _amount);
    }
}
