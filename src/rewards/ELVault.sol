// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/proxy/utils/Initializable.sol";
import "src/interfaces/IELVault.sol";
import "src/interfaces/IVNFT.sol";

/**
 * @title ELVault for managing rewards
 */
contract ELVault is IELVault, Ownable, ReentrancyGuard, Initializable {
    IVNFT public nftContract;
    address public liquidStakingAddress;

    // dao address
    address public dao;

    RewardMetadata[] public cumArr;
    uint256 public unclaimedRewards;
    uint256 public lastPublicSettle;
    uint256 public publicSettleLimit;

    uint256 public comission = 1000; // todo 给operator的执行层奖励抽成
    uint256 public operatorRewards;

    uint256 public liquidStakingGasHeight; // 标记流动性池子的gasHeight
    mapping(uint256 => uint256) public userGasHeight; // key tokenId ; value gasheight

    event ComissionChanged(uint256 _before, uint256 _after);
    event LiquidStakingChanged(address _before, address _after);
    event PublicSettleLimitChanged(uint256 _before, uint256 _after);
    event RewardClaimed(address _owner, uint256 _amount);
    event Transferred(address _to, uint256 _amount);
    event Settle(uint256 _blockNumber, uint256 _settleRewards);

    modifier onlyLiquidStaking() {
        require(liquidStakingAddress == msg.sender, "Not allowed to touch funds");
        _;
    }

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(address nftContract_, address _dao) external initializer {
        nftContract = IVNFT(nftContract_);
        dao = _dao;

        RewardMetadata memory r = RewardMetadata({
            value: 0,
            height: 0
        });

        cumArr.push(r);
        unclaimedRewards = 0;
        lastPublicSettle = 0;
        publicSettleLimit = 216000;
    }

    /**
     * @notice Computes the reward a nft has
     * @param tokenId - tokenId of the validator nft
     */
    function _rewards(uint256 tokenId) private view returns (uint256) {
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
    function _settle() private {
        uint256 outstandingRewards = address(this).balance - unclaimedRewards - operatorRewards;
        if (outstandingRewards == 0 || cumArr[cumArr.length - 1].height == block.number) {
            return;
        }

        uint256 operatorReward = (outstandingRewards * comission) / 10000;
        operatorRewards += operatorReward;
        outstandingRewards -= operatorReward;
        unclaimedRewards += outstandingRewards;

        uint256 averageRewards = outstandingRewards / nftContract.totalSupply();
        uint256 currentValue = cumArr[cumArr.length - 1].value + averageRewards;
        RewardMetadata memory r = RewardMetadata({
            value: currentValue,
            height: block.number
        });
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

    function batchRewards(uint256[] memory tokenIds) external view returns(uint256) {
        uint256 nftRewards;
        uint256 i;
        for (i = 0; i < tokenIds.length; i++) {
            nftRewards += _rewards(tokenIds[i]);
        }

        return nftRewards;
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
    function transfer(uint256 amount, address to) private {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }

    function claimRewardsOfLiquidStaking(uint256[] memory tokenIds)external nonReentrant onlyLiquidStaking returns(uint256) {
        uint256 nftRewards;
        uint256 i;
        for (i = 0; i < tokenIds.length; i++) {
            nftRewards += _rewards(tokenIds[i]);
        }

        unclaimedRewards -= nftRewards;

        transfer(nftRewards, liquidStakingAddress);

        emit RewardClaimed(liquidStakingAddress, nftRewards);

        return nftRewards;
    }

    /**
     * @notice Claims the rewards belonging to a validator nft and transfer it to the owner
     * @param tokenId - tokenId of the validator nft
     */
    function claimRewardsOfUser(uint256 tokenId) external nonReentrant onlyLiquidStaking returns(uint256) {
        address owner = nftContract.ownerOf(tokenId);
        uint256 nftRewards = _rewards(tokenId);
        
        unclaimedRewards -= nftRewards;
        transfer(nftRewards, owner);

        userGasHeight[tokenId] = cumArr[cumArr.length - 1].height;
        emit RewardClaimed(owner, nftRewards);

        return nftRewards;
    }

    /**
     * @notice Operater Claims the rewards 
    */
    function setUserNft(uint256 tokenId, uint256 number) external onlyLiquidStaking {
        userGasHeight[tokenId] = number;
    }

    function setLiquidStakingGasHeight(uint256 _gasHeight) external onlyLiquidStaking {
        liquidStakingGasHeight = _gasHeight;
    }

    /**
     * @notice Operater Claims the rewards 
     */
    function claimOperater(address to) external nonReentrant {
        transfer(operatorRewards, to);
        operatorRewards = 0;
    }

    /**
     * @notice Sets the liquidStaking address
     */
    function setLiquidStaking(address liquidStakingAddress_) external onlyDao {
        require(liquidStakingAddress_ != address(0), "LiquidStaking address provided invalid");
        emit LiquidStakingChanged(liquidStakingAddress, liquidStakingAddress_);
        liquidStakingAddress = liquidStakingAddress_;
    }

    /**
     * @notice Sets the `PublicSettleLimit`. Determines how frequently this contract can be spammed
     */
    function setPublicSettleLimit(uint256 publicSettleLimit_) external onlyOwner {
        emit PublicSettleLimitChanged(publicSettleLimit, publicSettleLimit_);
        publicSettleLimit = publicSettleLimit_;
    }

    /**
     * @notice Sets the comission. Comission is currently used to fund hardware costs
     */
    function setComission(uint256 comission_) external onlyDao {
        require(comission_ < 10000, "Comission cannot be 100%");
        emit ComissionChanged(comission, comission_);
        comission = comission_;
    }

    /**
      * @notice set dao vault address
      */
    function setDaoAddress(address _dao) external onlyDao {
        dao = _dao;
    }

    function liquidStaking() external view returns(address) {
        return liquidStakingAddress;
    }

    receive() external payable{}
}