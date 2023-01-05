// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../interfaces/ILiquidStaking.sol";

contract BeaconOracle is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    // The epoch of each frame (currently 24h for 225)
    uint64 internal constant EPOCHS_PER_FRAME = 225;

    // Number of slots corresponding to each epoch
    uint64 internal constant SLOTS_PER_EPOCH = 32;

    // Base time (default beacon creation time)
    uint64 internal constant GENESIS_TIME = 1606824023;

    // Seconds for each slot
    uint64 internal constant SECONDS_PER_SLOT = 12;

    // The expected epoch Id is required by oracle for report Beacon
    uint256 private _expected_epoch_id;

    // todo: reportBeacon value

    // todo: reportBeacon status

    // todo: Identify if oracle is calling liquid Staking
    address public liquidStakingContract;

    function initalizeOracle(address _liquidStaking) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        liquidStakingContract = _liquidStaking;
        // So the initial is the first epochId
        _expected_epoch_id = _getFirstEpochOfDay(_getCurrentEpochId()) + EPOCHS_PER_FRAME;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _getFirstEpochOfDay(uint256 _epochId) internal pure returns (uint256) {
        return (_epochId / EPOCHS_PER_FRAME) * EPOCHS_PER_FRAME;
    }

    function _getCurrentEpochId() internal view returns (uint256) {
        // The number of epochs after the base time
        return (_getTime() - GENESIS_TIME) / (SLOTS_PER_EPOCH * SECONDS_PER_SLOT);
    }

    function _getTime() internal view returns (uint256) {
        return block.timestamp;
    }

    function getQuorum() internal returns (uint256) {
        ILiquidStaking liquidStaking = getLiquidStaking();
        uint256 n = liquidStaking.getNodeOperatorCount() * 2 / 3;
        return 1 + n;
    }

    // todo 重新设置 epochId  只要是operator成员就可以设置吗？  权限问题
    function resetExpectedEpochId() external onlyOwner {
        // 判断是否是白名单Operator
        // todo 权限是否冲突？
        require(getLiquidStaking().isKingHashOperator(msg.sender), "Not part of DAOs' trusted list of addresses");
        _expected_epoch_id = _getFirstEpochOfDay(_getCurrentEpochId()) + EPOCHS_PER_FRAME;
    }

    function getLiquidStaking() public view returns (ILiquidStaking) {
        return ILiquidStaking(liquidStakingContract);
    }

    function getExpectedEpochId() public view returns (uint256) {
        return _expected_epoch_id;
    }

    // todo 存在问题 一轮投票后 未满足quorum 需要清除一些基准数据：submittedReports hasSubmitted
    // todo 需要提供一种方式，让oracle获得 isReported
    // todo 可以添加一些 emit 供oracle进行订阅
    // todo 重新设置结构
    function reportBeacon(uint256 epochId, uint256 data, bytes32 nodeRankingCommitment) external {
        require(getKingHash().isKingHashOperator(msg.sender), "Not part of DAOs' trusted list of addresses");
        require(epochId == EXPECTED_EPOCH_POSITION.getStorageUint256(), "The epoch submitted is not expected.");
        require(hasSubmitted[epochId][msg.sender] == false, "This msg.sender has already submitted the vote.");

        // 结果 hash 作为 k
        bytes32 hash = keccak256(abi.encode(data, nodeRankingCommitment));
        submittedReports[epochId][hash]++;

        hasSubmitted[epochId][msg.sender] = true;

        uint256 quorum = getQuorum();
        if (submittedReports[epochId][hash] > quorum) {
            pushReport(data, nodeRankingCommitment);
        }
    }

    // todo
    function pushReport(uint256 data, bytes32 nodeRankingCommitment) internal {
        ILiquidStaking liquidStaking = getLiquidStaking();
        liquidStaking.handleOracleReport(data, nodeRankingCommitment);
        uint256 nextExpectedEpoch = EXPECTED_EPOCH_POSITION.getStorageUint256() + EPOCHS_PER_FRAME;
        // todo report后会重新设置 epochId  如果当天report失败了，那么想让epochId加一天 只能手动  resetEpectedEpoch
        _expected_epoch_id = nextExpectedEpoch;
    }


}
