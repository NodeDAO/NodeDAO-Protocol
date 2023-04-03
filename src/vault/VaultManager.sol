// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";

contract VaultManager is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    ILiquidStaking public liquidStakingContract;
    IVNFT public vNFTContract;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    address public withdrawOracleContractAddress;
    address public clVaultContractAddresss;
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

    modifier onlyWithdrawOracle() {
        require(withdrawOracleContractAddress == msg.sender, "Not allowed to touch funds");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address _dao,
        address _liquidStakingAddress,
        address _nVNFTContractAddress,
        address _nodeOperatorRegistryAddress,
        address _withdrawOracleContractAddress,
        address _clVaultContractAddresss
    ) public initializer {
        liquidStakingContract = ILiquidStaking(_liquidStakingAddress);
        vNFTContract = IVNFT(_nVNFTContractAddress);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryAddress);
        withdrawOracleContractAddress = _withdrawOracleContractAddress;
        clVaultContractAddresss = _clVaultContractAddresss;

        dao = _dao;
        daoElComissionRate = 300;
    }

    function reportConsensusData(
        uint256[] memory _operatorIds,
        uint256[] memory _clRewards,
        uint256[] memory _exitClCapitals,
        uint256[] memory _exitTokenIds,
        uint256[] memory _exitBlockNumbers,
        uint256 _thisTotalWithdrawAmount
    ) external onlyWithdrawOracle {
        require(
            _operatorIds.length == _clRewards.length && _operatorIds.length == _exitClCapitals.length
                && _operatorIds.length != 0,
            "_operatorIds _clRewards _exitClCapital must have the same length"
        );

        uint256[] memory amouts = new uint256[](_operatorIds.length);
        uint256 slashNumber = 0;
        uint256 totalAmount = 0;
        uint256 totalExitCapital = 0;
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 exitClCapital = _exitClCapitals[i];
            uint256 _amount = _clRewards[i] + exitClCapital;
            amouts[i] = _amount;
            totalAmount += _amount;
            totalExitCapital += exitClCapital;
            if (exitClCapital != 0 && 32 ether > exitClCapital) {
                slashNumber += 1;
            }
        }

        require(totalAmount == _thisTotalWithdrawAmount, "_thisTotalWithdrawAmount check failed");
        require(_exitTokenIds.length * 32 ether >= totalExitCapital, "totalExitCapital check failed");

        uint256[] memory slashOperators = new uint256[] (slashNumber);
        uint256[] memory slashAmounts = new uint256[] (slashNumber);
        uint256 slashIndex = 0;
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 exitClCapital = _exitClCapitals[i];
            if (exitClCapital != 0 && 32 ether > exitClCapital) {
                slashOperators[slashIndex] = i;
                slashAmounts[slashIndex] = 32 ether - exitClCapital;
                slashIndex += 1;
            }
        }

        liquidStakingContract.reinvestClRewards(_operatorIds, amouts);
        liquidStakingContract.slashOperator(slashOperators, slashAmounts);

        // nft exit
        liquidStakingContract.nftExitHandle(_exitTokenIds, _exitBlockNumbers);
    }

    function settleAndReinvestElReward(uint256[] memory _operatorIds) external {
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
        uint256[] memory operatorElComissionRate = nodeOperatorRegistryContract.getOperatorComissionRate(_operatorIds);
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
        if (outstandingRewards >= 1 ether) {
            return 0;
        }

        uint256 operatorNftCounts = vNFTContract.getNftCountsOfOperator(operatorId);
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

        unclaimedRewardsMap[operatorId] += outstandingRewards - reinvestRewards;

        if (cumArr.length == 0) {
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

    function claimRewardsOfUser(uint256[] memory _tokenIds) external {
        uint256 operatorId = vNFTContract.operatorOf(_tokenIds[0]);
        uint256[] memory gasHeights = vNFTContract.getUsernftGasHeight(_tokenIds);
        uint256[] memory exitBlockNumbers = vNFTContract.getNftExitBlockNumbers(_tokenIds);
        uint256[] memory amounts = new uint256[] (_tokenIds.length);
        uint256 totalNftRewards = 0;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            require(operatorId == vNFTContract.operatorOf(tokenId), "Must be the tokenId of the same operator");
            uint256 nftRewards = _rewards(operatorId, tokenId, gasHeights[0], exitBlockNumbers[i]);
            amounts[i] = nftRewards;
            totalNftRewards += nftRewards;
        }

        uint256 gasHeight = settleCumArrMap[operatorId][settleCumArrMap[operatorId].length - 1].height;
        liquidStakingContract.claimRewardsOfUser(operatorId, _tokenIds, amounts, gasHeight);

        emit RewardClaimed(vNFTContract.ownerOf(_tokenIds[0]), totalNftRewards);
    }

    function rewards(uint256[] memory _tokenIds) external view returns (uint256) {
        uint256 operatorId = vNFTContract.operatorOf(_tokenIds[0]);
        uint256[] memory gasHeights = vNFTContract.getUsernftGasHeight(_tokenIds);
        uint256[] memory exitBlockNumbers = vNFTContract.getNftExitBlockNumbers(_tokenIds);
        uint256 totalNftRewards = 0;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            require(operatorId == vNFTContract.operatorOf(tokenId), "Must be the tokenId of the same operator");
            uint256 nftRewards = _rewards(operatorId, tokenId, gasHeights[0], exitBlockNumbers[i]);
            totalNftRewards += nftRewards;
        }

        return totalNftRewards;
    }

    function _rewards(uint256 _operatorId, uint256 _tokenId, uint256 gasHeight, uint256 exitBlockNumber)
        internal
        view
        returns (uint256)
    {
        RewardMetadata[] memory cumArr = settleCumArrMap[_operatorId];

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
            uint256 highIndex = high - 1;
        }

        // At this point `low` is the exclusive upper bound. We will use it.
        return cumArr[highIndex].value - cumArr[low - 1].value;
    }

    function claimRewardsOfOperator(uint256 _operatorId) external {
        uint256 operatorRewards = operatorRewardsMap[_operatorId];
        operatorRewardsMap[_operatorId] = 0;
        liquidStakingContract.claimRewardsOfOperator(_operatorId, operatorRewards);
        emit OperatorClaimRewards(_operatorId, operatorRewards);
    }

    function claimRewardsOfDao(uint256[] memory _operatorIds) external {
        uint256[] memory _rewards = new uint256[](_operatorIds.length);
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 _operatorId = _operatorIds[i];
            uint256 _daoRewards = daoRewardsMap[_operatorId];
            _rewards[i] = _daoRewards;
            daoRewardsMap[_operatorId] = 0;
            emit DaoClaimRewards(_operatorId, _daoRewards);
        }

        liquidStakingContract.claimRewardsOfDao(_operatorIds, _rewards);
    }
}
