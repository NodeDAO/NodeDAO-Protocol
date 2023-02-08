// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/utils/math/Math.sol";
import "src/interfaces/IELVault.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";

/**
 * @title ELVault for managing rewards
 */
contract ELVault is IELVault, ReentrancyGuard, Initializable {
    using Math for uint256;

    IVNFT public vNFTContract;
    ILiquidStaking public liquidStakingContract;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;

    uint256 public operatorId;
    // dao address
    address public dao;

    // Average cumulative reward record for settlement
    RewardMetadata[] public cumArr;
    // unclaimed Rewards
    uint256 public unclaimedRewards;
    uint256 public lastPublicSettle;
    uint256 public publicSettleLimit;

    // Execution layer reward ratio
    uint256 public comissionRate;
    uint256 public daoComissionRate;
    uint256 public operatorRewards;
    uint256 public daoRewards;

    // liquidStaking nft gas height
    uint256 public liquidStakingGasHeight;
    // liquidStaking reward
    uint256 public liquidStakingReward;

    // key tokenId; value gasheight
    mapping(uint256 => uint256) public userGasHeight;

    uint256 public userNftsCount;

    event ComissionRateChanged(uint256 _before, uint256 _after);
    event LiquidStakingChanged(address _before, address _after);
    event PublicSettleLimitChanged(uint256 _before, uint256 _after);
    event RewardClaimed(address _owner, uint256 _amount);
    event Transferred(address _to, uint256 _amount);
    event Settle(uint256 _blockNumber, uint256 _settleRewards);

    modifier onlyLiquidStaking() {
        require(address(liquidStakingContract) == msg.sender, "Not allowed to touch funds");
        _;
    }

    modifier onlyDao() {
        require(msg.sender == dao, "PERMISSION_DENIED");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    /**
     * @notice initialize Vault Contract
     * @param _nVNFTContractAddress vNFT contract address
     * @param dao_ Dao Address
     * @param operatorId_ operator Id
     * @param liquidStakingAddress_ liquidStaking contract address
     * @param nodeOperatorRegistryAddress_ nodeOperatorRegistry Address
     */
    function initialize(
        address _nVNFTContractAddress,
        address dao_,
        uint256 operatorId_,
        address liquidStakingAddress_,
        address nodeOperatorRegistryAddress_
    ) external initializer {
        vNFTContract = IVNFT(_nVNFTContractAddress);
        dao = dao_;

        RewardMetadata memory r = RewardMetadata({value: 0, height: 0});

        cumArr.push(r);
        unclaimedRewards = 0;
        lastPublicSettle = 0;
        publicSettleLimit = 216000;
        comissionRate = 1000;
        daoComissionRate = 3000;
        operatorId = operatorId_;
        liquidStakingContract = ILiquidStaking(liquidStakingAddress_);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(nodeOperatorRegistryAddress_);
    }

    /**
     * @notice Computes the reward a nft has
     * @param tokenId - tokenId of the validator nft
     */
    function _rewards(uint256 tokenId) internal view returns (uint256) {
        uint256 gasHeight = userGasHeight[tokenId];
        if (gasHeight == 0) {
            gasHeight = liquidStakingGasHeight;
        }

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

        // At this point `low` is the exclusive upper bound. We will use it.
        return cumArr[cumArr.length - 1].value - cumArr[low - 1].value;
    }

    /**
     * @notice Settles outstanding rewards
     * @dev Current active validator nft will equally recieve all rewards earned in this era
     */
    function _settle() internal {
        uint256 outstandingRewards = address(this).balance - unclaimedRewards - operatorRewards - daoRewards;
        if (outstandingRewards == 0 || cumArr[cumArr.length - 1].height == block.number) {
            return;
        }

        uint256 comission = (outstandingRewards * comissionRate) / 10000;
        uint256 daoReward = (comission * daoComissionRate) / 10000;
        daoRewards += daoReward;
        operatorRewards += comission - daoReward;

        outstandingRewards -= comission;
        unclaimedRewards += outstandingRewards;

        uint256 operatorNftCounts = vNFTContract.getNftCountsOfOperator(operatorId);
        uint256 averageRewards = outstandingRewards / operatorNftCounts;

        liquidStakingReward += averageRewards * (operatorNftCounts - userNftsCount);

        uint256 currentValue = cumArr[cumArr.length - 1].value + averageRewards;
        RewardMetadata memory r = RewardMetadata({value: currentValue, height: block.number});
        cumArr.push(r);

        emit Settle(block.number, averageRewards);
    }

    /**
     * @notice Computes the reward a nft has
     * @param tokenId - tokenId of the validator nft
     */
    function rewards(uint256 tokenId) external view override returns (uint256) {
        return _rewards(tokenId);
    }

    /**
     * @notice get liquidStaking pool reward
     */
    function getLiquidStakingReward() external view returns (uint256) {
        return liquidStakingReward;
    }

    /**
     * @notice Gets the last recorded height which rewards was last dispersed + 1
     */
    function rewardsHeight() external view override returns (uint256) {
        return cumArr[cumArr.length - 1].height + 1;
    }

    /**
     * @notice Returns an array of recent `RewardMetadata`
     * @param amt - The amount of `RewardMetdata` to return, ordered according to the most recent
     */
    function rewardsAndHeights(uint256 amt) external view override returns (RewardMetadata[] memory) {
        if (amt >= cumArr.length) {
            return cumArr;
        }

        RewardMetadata[] memory r = new RewardMetadata[](amt);

        for (uint256 i = 0; i < amt; i++) {
            r[i] = cumArr[cumArr.length - 1 - i];
        }

        return r;
    }

    /**
     * @notice Settles outstanding rewards
     * @dev Current active validator nft will equally recieve all rewards earned in this era
     */
    function settle() external override onlyLiquidStaking {
        _settle();
    }

    /**
     * @notice Settles outstanding rewards in the event there is no change in amount of validators
     * @dev Current active validator nft will equally recieve  all rewards earned in this era
     */
    function publicSettle() external override {
        // prevent spam attack
        if (lastPublicSettle + publicSettleLimit > block.number) {
            return;
        }

        _settle();
        lastPublicSettle = block.number;
    }

    //slither-disable-next-line arbitrary-send
    function transfer(uint256 amount, address to) internal {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }

    /**
     * @notice Reinvesting rewards belonging to the liquidStaking pool
     */
    function reinvestmentOfLiquidStaking() external nonReentrant onlyLiquidStaking returns (uint256) {
        uint256 nftRewards = liquidStakingReward;
        unclaimedRewards -= nftRewards;
        liquidStakingReward = 0;
        liquidStakingContract.receiveRewards{value: nftRewards}(nftRewards);

        emit RewardClaimed(address(liquidStakingContract), nftRewards);

        return nftRewards;
    }

    /**
     * @notice Claims the rewards belonging to a validator nft and transfer it to the owner
     * @param tokenId - tokenId of the validator nft
     */
    function claimRewardsOfUser(uint256 tokenId) external nonReentrant onlyLiquidStaking returns (uint256) {
        require(userGasHeight[tokenId] != 0, "must be user tokenId");

        address owner = vNFTContract.ownerOf(tokenId);
        uint256 nftRewards = _rewards(tokenId);

        unclaimedRewards -= nftRewards;
        transfer(nftRewards, owner);

        userGasHeight[tokenId] = cumArr[cumArr.length - 1].height;
        emit RewardClaimed(owner, nftRewards);

        return nftRewards;
    }

    /**
     * @notice Set the gas height of user nft
     */
    function setUserNft(uint256 tokenId, uint256 number) external onlyLiquidStaking {
        if (number == 0) {
            userNftsCount -= 1;
        } else {
            userNftsCount += 1;
        }

        userGasHeight[tokenId] = number;
    }

    /**
     * @notice Set the gas height of liquidStaking nft
     */
    function setLiquidStakingGasHeight(uint256 _gasHeight) external onlyLiquidStaking {
        liquidStakingGasHeight = _gasHeight;
    }

    /**
     * @notice Operater Claims the rewards
     */
    function claimOperatorRewards() external nonReentrant onlyLiquidStaking returns (uint256) {
        uint256 rewards = operatorRewards;
        operatorRewards = 0;

        uint256 requireVault = 0;
        uint256 operatorNftCounts = vNFTContract.getNftCountsOfOperator(operatorId);
        if (operatorNftCounts <= 100) {
            requireVault = (operatorNftCounts * 10 / 100) * 1 ether;
        } else {
            requireVault = operatorNftCounts.sqrt() * 1 ether;
        }

        uint256 nowPledge = nodeOperatorRegistryContract.getPledgeBalanceOfOperator(operatorId);
        require(nowPledge >= requireVault, "Insufficient pledge balance");

        address[] memory rewardAddresses;
        uint256[] memory ratios;
        (rewardAddresses, ratios) = nodeOperatorRegistryContract.getNodeOperatorRewardSetting(operatorId);
        require(rewardAddresses.length != 0, "Invalid rewardAddresses");

        uint256 totalAmount = 0;
        uint256 totalRatios = 0;
        for (uint256 i = 0; i < rewardAddresses.length; i++) {
            uint256 ratio = ratios[i];
            totalRatios += ratio;

            if (i == rewardAddresses.length - 1) {
                transfer(rewards - totalAmount, rewardAddresses[i]);
            } else {
                uint256 reward = rewards * ratio / 100;
                transfer(reward, rewardAddresses[i]);
                totalAmount += reward;
            }
        }

        require(totalRatios == 100, "Invalid ratio");

        return rewards;
    }

    /**
     * @notice Dao Claims the rewards
     */
    function claimDaoRewards(address to) external nonReentrant onlyLiquidStaking returns (uint256) {
        uint256 rewards = daoRewards;
        daoRewards = 0;
        transfer(rewards, to);
        return rewards;
    }

    /**
     * @notice Sets the liquidStaking address
     */
    function setLiquidStaking(address liquidStaking_) external onlyDao {
        require(liquidStaking_ != address(0), "LiquidStaking address provided invalid");
        emit LiquidStakingChanged(address(liquidStakingContract), liquidStaking_);
        liquidStakingContract = ILiquidStaking(liquidStaking_);
    }

    /**
     * @notice Sets the `PublicSettleLimit`. Determines how frequently this contract can be spammed
     */
    function setPublicSettleLimit(uint256 publicSettleLimit_) external onlyDao {
        emit PublicSettleLimitChanged(publicSettleLimit, publicSettleLimit_);
        publicSettleLimit = publicSettleLimit_;
    }

    /**
     * @notice Sets the comission.
     */
    function setComissionRate(uint256 comissionRate_) external onlyDao {
        require(comissionRate_ < 10000, "Comission cannot be 100%");
        emit ComissionRateChanged(comissionRate, comissionRate_);
        comissionRate = comissionRate_;
    }

    /**
     * @notice Sets the Dao comission.
     */
    function setDaoComissionRate(uint256 comissionRate_) external onlyDao {
        require(comissionRate_ < 10000, "Comission cannot be 100%");
        emit ComissionRateChanged(daoComissionRate, comissionRate_);
        daoComissionRate = comissionRate_;
    }

    /**
     * @notice set dao address
     */
    function setDaoAddress(address _dao) external onlyDao {
        dao = _dao;
    }

    receive() external payable {}
}
