// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import {WithdrawInfo, ExitValidatorInfo} from "src/library/ConsensusStruct.sol";
import "src/interfaces/IOperatorSlash.sol";

contract VaultManager is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    ILiquidStaking public liquidStakingContract;
    IVNFT public vNFTContract;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    IOperatorSlash public operatorSlashContract;
    address public withdrawOracleContractAddress;
    address public dao;

    // el settle
    struct RewardMetadata {
        uint256 value;
        uint256 height;
    }

    uint256 public daoElComissionRate;
    mapping(uint256 => RewardMetadata[]) public settleCumArrMap;
    mapping(uint256 => uint256) public unclaimedRewardsMap;
    mapping(uint256 => uint256) public operatorRewardsMap;
    mapping(uint256 => uint256) public daoRewardsMap;

    event ELRewardSettleAndReinvest(uint256[] _operatorIds, uint256[] _reinvestAmounts);
    event Settle(uint256 _blockNumber, uint256 _settleRewards, uint256 _operatorNftCounts, uint256 _averageRewards);
    event RewardClaimed(address _owner, uint256 _amount);
    event OperatorClaimRewards(uint256 _operatorId, uint256 _rewards);
    event DaoClaimRewards(uint256 _operatorId, uint256 _rewards);

    error PermissionDenied();
    error InvalidParameter();
    error WithdrawAmountCheckFailed();
    error SlashAmountCheckFailed();
    error MustSameOperator();
    error NeverSettled();
    error InsufficientMargin();
    error InvalidRewardAddr();
    error InvalidRewardRatio();

    modifier onlyWithdrawOracle() {
        if (withdrawOracleContractAddress != msg.sender) revert PermissionDenied();
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address _dao,
        address _liquidStakingAddress,
        address _nVNFTContractAddress,
        address _nodeOperatorRegistryAddress,
        address _withdrawOracleContractAddress,
        address _operatorSlashContract
    ) public initializer {
        liquidStakingContract = ILiquidStaking(_liquidStakingAddress);
        vNFTContract = IVNFT(_nVNFTContractAddress);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryAddress);
        withdrawOracleContractAddress = _withdrawOracleContractAddress;
        operatorSlashContract = IOperatorSlash(_operatorSlashContract);

        dao = _dao;
        daoElComissionRate = 300;
    }

    /**
     * @notice Receive the oracle machine consensus layer information, initiate re-investment consensus layer rewards, trigger and update the exited nft
     * @param _withdrawInfo withdraw info
     * @param _exitValidatorInfo exit validator info
     * @param _userNftExitDelayedTokenIds nft with delayed exit
     * @param _largeExitDelayedRequestIds large Requests for Delayed Exit
     * @param _thisTotalWithdrawAmount The total settlement amount reported this time
     */
    function reportConsensusData(
        // clCapital is the principal of nft exit held by the protocol
        WithdrawInfo[] memory _withdrawInfo,
        // Here are all the nft exit infomation
        ExitValidatorInfo[] memory _exitValidatorInfo,
        uint256[] memory _userNftExitDelayedTokenIds, // user nft
        uint256[] memory _largeExitDelayedRequestIds, // large unstake request id
        uint256 _thisTotalWithdrawAmount
    ) external onlyWithdrawOracle {
        uint256[] memory operatorIds = new uint256[](_withdrawInfo.length);
        uint256[] memory amouts = new uint256[](_withdrawInfo.length);
        uint256 totalAmount = 0;
        uint256 systemTotalExitCapital = 0;
        for (uint256 i = 0; i < _withdrawInfo.length; ++i) {
            WithdrawInfo memory wInfo = _withdrawInfo[i];
            operatorIds[i] = wInfo.operatorId;
            uint256 exitClCapital = wInfo.clCapital;
            uint256 _amount = wInfo.clReward + exitClCapital;
            amouts[i] = _amount;
            totalAmount += _amount;
            systemTotalExitCapital += exitClCapital;
        }

        if (totalAmount != _thisTotalWithdrawAmount) revert WithdrawAmountCheckFailed();

        uint256[] memory exitTokenIds = new uint256[] (_exitValidatorInfo.length);
        uint256[] memory slashAmounts = new uint256[] (_exitValidatorInfo.length);
        uint256[] memory exitBlockNumbers = new uint256[] (_exitValidatorInfo.length);
        uint256 systemTotalSlashAmounts = 0;
        uint256 systemTotalExitNumber = 0;
        address system = address(liquidStakingContract);
        for (uint256 i = 0; i < _exitValidatorInfo.length; ++i) {
            ExitValidatorInfo memory vInfo = _exitValidatorInfo[i];
            exitTokenIds[i] = vInfo.exitTokenId;
            slashAmounts[i] = vInfo.slashAmount;
            exitBlockNumbers[i] = vInfo.exitBlockNumber;
            if (vNFTContract.ownerOf(vInfo.exitTokenId) == system) {
                systemTotalSlashAmounts += vInfo.slashAmount;
                systemTotalExitNumber += 1;
            }
        }

        if (systemTotalExitNumber * 32 ether != systemTotalExitCapital + systemTotalSlashAmounts) {
            revert SlashAmountCheckFailed();
        }

        liquidStakingContract.reinvestClRewards(operatorIds, amouts);

        if (exitTokenIds.length != 0 || slashAmounts.length != 0) {
            operatorSlashContract.slashOperator(exitTokenIds, slashAmounts);
        }

        if (_userNftExitDelayedTokenIds.length != 0 || _largeExitDelayedRequestIds.length != 0) {
            operatorSlashContract.slashOfExitDelayed(_userNftExitDelayedTokenIds, _largeExitDelayedRequestIds);
        }

        // nft exit
        if (exitTokenIds.length != 0 || exitBlockNumbers.length != 0) {
            liquidStakingContract.nftExitHandle(exitTokenIds, exitBlockNumbers);
        }

        _settleAndReinvestElReward(operatorIds);
    }

    /**
     * @notice Settlement and reinvestment execution layer rewards
     * @param _operatorIds operator id
     */
    function settleAndReinvestElReward(uint256[] memory _operatorIds) external {
        _settleAndReinvestElReward(_operatorIds);
    }

    function _settleAndReinvestElReward(uint256[] memory _operatorIds) internal {
        uint256[] memory reinvestAmounts;
        bool isSettle;
        (reinvestAmounts, isSettle) = _elSettle(_operatorIds);
        if (isSettle) {
            liquidStakingContract.reinvestElRewards(_operatorIds, reinvestAmounts);
            emit ELRewardSettleAndReinvest(_operatorIds, reinvestAmounts);
        }
    }

    function _elSettle(uint256[] memory _operatorIds) internal returns (uint256[] memory, bool) {
        uint256[] memory reinvestAmounts = new uint256[] (_operatorIds.length);
        uint256[] memory operatorElComissionRate;
        operatorElComissionRate = nodeOperatorRegistryContract.getOperatorComissionRate(_operatorIds);

        bool isSettle = false;
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 operatorId = _operatorIds[i];
            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);

            uint256 _reinvest = _settle(operatorId, vaultContractAddress, operatorElComissionRate[i]);
            if (_reinvest > 0) {
                isSettle = true;
            }
            reinvestAmounts[i] = _reinvest;
        }

        return (reinvestAmounts, isSettle);
    }

    function _settle(uint256 operatorId, address vaultContractAddress, uint256 comissionRate)
        internal
        returns (uint256)
    {
        RewardMetadata[] memory cumArr = settleCumArrMap[operatorId];
        uint256 outstandingRewards = address(vaultContractAddress).balance - unclaimedRewardsMap[operatorId]
            - operatorRewardsMap[operatorId] - daoRewardsMap[operatorId];
        if (outstandingRewards < 1 ether) {
            return 0;
        }

        uint256 operatorNftCounts = vNFTContract.getActiveNftCountsOfOperator(operatorId);
        if (operatorNftCounts == 0) {
            return 0;
        }

        uint256 operatorReward = (outstandingRewards * comissionRate) / 10000;

        uint256 daoReward = (outstandingRewards * daoElComissionRate) / 10000;
        operatorRewardsMap[operatorId] += operatorReward;
        daoRewardsMap[operatorId] += daoReward;
        outstandingRewards = outstandingRewards - operatorReward - daoReward;
        uint256 averageRewards = outstandingRewards / operatorNftCounts;
        uint256 userNftCounts = vNFTContract.getUserActiveNftCountsOfOperator(operatorId);
        uint256 reinvestRewards = averageRewards * (operatorNftCounts - userNftCounts);

        unclaimedRewardsMap[operatorId] += (outstandingRewards - reinvestRewards);
        if (cumArr.length == 0) {
            RewardMetadata memory r0 = RewardMetadata({value: 0, height: 0});
            settleCumArrMap[operatorId].push(r0);
            RewardMetadata memory r = RewardMetadata({value: averageRewards, height: block.number});
            settleCumArrMap[operatorId].push(r);
        } else {
            uint256 currentValue = cumArr[cumArr.length - 1].value + averageRewards;
            RewardMetadata memory r = RewardMetadata({value: currentValue, height: block.number});
            settleCumArrMap[operatorId].push(r);
        }

        emit Settle(block.number, outstandingRewards, operatorNftCounts, averageRewards);

        return reinvestRewards;
    }

    /**
     * @notice Users claim vNFT rewards, supports multiple nft, but must be under one operator
     * @param _tokenIds vNFT tokenIds
     */
    function claimRewardsOfUser(uint256[] memory _tokenIds) external {
        address owner = vNFTContract.ownerOf(_tokenIds[0]);
        uint256 operatorId = vNFTContract.operatorOf(_tokenIds[0]);
        uint256[] memory gasHeights = vNFTContract.getUserNftGasHeight(_tokenIds);
        uint256[] memory exitBlockNumbers = vNFTContract.getNftExitBlockNumbers(_tokenIds);
        uint256[] memory amounts = new uint256[] (_tokenIds.length);
        uint256 totalNftRewards = 0;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            if (owner != vNFTContract.ownerOf(tokenId)) revert PermissionDenied();
            if (operatorId != vNFTContract.operatorOf(tokenId)) revert MustSameOperator();
            uint256 nftRewards = _rewards(operatorId, gasHeights[0], exitBlockNumbers[i]);
            amounts[i] = nftRewards;
            totalNftRewards += nftRewards;
        }
        unclaimedRewardsMap[operatorId] -= totalNftRewards;
        uint256 gasHeight = settleCumArrMap[operatorId][settleCumArrMap[operatorId].length - 1].height;
        liquidStakingContract.claimRewardsOfUser(operatorId, _tokenIds, totalNftRewards, gasHeight, owner);
        emit RewardClaimed(owner, totalNftRewards);
    }

    /**
     * @notice Computes the reward a nft has
     * @param _tokenIds - tokenId of the validator nft
     */
    function rewards(uint256[] memory _tokenIds) external view returns (uint256) {
        uint256 operatorId = vNFTContract.operatorOf(_tokenIds[0]);
        uint256[] memory gasHeights = vNFTContract.getUserNftGasHeight(_tokenIds);
        uint256[] memory exitBlockNumbers = vNFTContract.getNftExitBlockNumbers(_tokenIds);

        uint256 totalNftRewards = 0;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            if (operatorId != vNFTContract.operatorOf(tokenId)) revert MustSameOperator();
            uint256 nftRewards = _rewards(operatorId, gasHeights[0], exitBlockNumbers[i]);
            totalNftRewards += nftRewards;
        }

        return totalNftRewards;
    }

    function _rewards(uint256 _operatorId, uint256 gasHeight, uint256 exitBlockNumber)
        internal
        view
        returns (uint256)
    {
        RewardMetadata[] memory cumArr = settleCumArrMap[_operatorId];
        if (cumArr.length == 0) revert NeverSettled();
        uint256 low = 0;
        uint256 high = cumArr.length;
        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (cumArr[mid].height > gasHeight) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        uint256 lowIndex = low - 1;
        uint256 highIndex = cumArr.length - 1;
        if (exitBlockNumber != 0) {
            low = 0;
            high = cumArr.length;
            while (low < high) {
                uint256 mid = (low + high) >> 1;

                if (cumArr[mid].height > exitBlockNumber) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
            highIndex = high - 1;
        }
        // At this point `low` is the exclusive upper bound. We will use it.
        return cumArr[highIndex].value - cumArr[lowIndex].value;
    }

    /**
     * @notice The operator claims the operation reward
     * @param _operatorId operator Id
     */
    function claimRewardsOfOperator(uint256 _operatorId) external {
        uint256 pledgeBalance = 0;
        uint256 requirBalance = 0;
        (pledgeBalance, requirBalance) = nodeOperatorRegistryContract.getPledgeInfoOfOperator(_operatorId);
        if (pledgeBalance < requirBalance) revert InsufficientMargin();

        uint256 operatorRewards = operatorRewardsMap[_operatorId];
        operatorRewardsMap[_operatorId] = 0;

        address[] memory rewardAddresses;
        uint256[] memory ratios;
        (rewardAddresses, ratios) = nodeOperatorRegistryContract.getNodeOperatorRewardSetting(_operatorId);
        if (rewardAddresses.length == 0) revert InvalidRewardAddr();
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
        uint256[] memory rewards = new uint256[] (rewardAddresses.length);
        uint256 totalAmount = 0;
        uint256 totalRatios = 0;
        for (uint256 i = 0; i < rewardAddresses.length; ++i) {
            uint256 ratio = ratios[i];
            totalRatios += ratio;

            // If it is the last reward address, calculate by subtraction
            if (i == rewardAddresses.length - 1) {
                rewards[i] = operatorRewards - totalAmount;
            } else {
                uint256 reward = operatorRewards * ratio / 100;
                rewards[i] = reward;
                totalAmount += reward;
            }
        }

        if (totalRatios != 100) revert InvalidRewardRatio();

        liquidStakingContract.claimRewardsOfOperator(_operatorId, rewardAddresses, rewards);
        emit OperatorClaimRewards(_operatorId, operatorRewards);
    }

    /**
     * @notice The dao claims to belong to the dao reward
     * @param _operatorIds operators Id
     */
    function claimRewardsOfDao(uint256[] memory _operatorIds) external {
        uint256[] memory daoRewards = new uint256[](_operatorIds.length);
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 _operatorId = _operatorIds[i];
            uint256 _daoRewards = daoRewardsMap[_operatorId];
            daoRewards[i] = _daoRewards;
            daoRewardsMap[_operatorId] = 0;
            emit DaoClaimRewards(_operatorId, _daoRewards);
        }

        liquidStakingContract.claimRewardsOfDao(_operatorIds, daoRewards);
    }
}
