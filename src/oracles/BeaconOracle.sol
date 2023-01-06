// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/interfaces/IBeaconOracle.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";

/**
  * @title Beacon Oracle and Dao
  *
  * BeaconOracle data acquisition and verification
  * Dao management
  */
contract BeaconOracle is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable, IBeaconOracle {

    // Dao member list
    address[] public daoMembers;

    // The epoch of each frame (currently 24h for 225)
    uint64 internal constant EPOCHS_PER_FRAME = 225;

    // Number of slots corresponding to each epoch
    uint64 internal constant SLOTS_PER_EPOCH = 32;

    // Base time (default beacon creation time)
    uint64 internal constant GENESIS_TIME = 1606824023;

    // Seconds for each slot
    uint64 internal constant SECONDS_PER_SLOT = 12;

    // The expected epoch Id is required by oracle for report Beacon
    uint256 public expectedEpochId;

    // k: hash of the uploaded result v: The number of times the same result has been uploaded
    mapping(bytes32 => uint256) internal submittedReports;

    // k:operator address v: Whether to send
    mapping(address => bool) internal hasSubmitted;

    // Whether the current frame has reached Quorum
    bool public isToQuorum;

    // current reportBeacon beaconBalances
    uint256 public beaconBalances;

    // current reportBeacon beaconValidators
    uint32 public beaconActiveValidators;

    address public liquidStakingContract;

    address public nodeOperatorsContract;

    function initalizeOracle(address _liquidStaking, address _nodeOperatorsContract, address[] memory _daoMembers) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        liquidStakingContract = _liquidStaking;
        nodeOperatorsContract = _nodeOperatorsContract;
        daoMembers = _daoMembers;
        // So the initial is the first epochId
        expectedEpochId = _getFirstEpochOfDay(_getCurrentEpochId()) + EPOCHS_PER_FRAME;
    }

    modifier onlyDaoMember {
        require(daoMembers.length > 0, "DaoMembers is empty");
        //        require(daoMembers.indexOf(msg.sender) >= 0, "Sender is not a Dao's member");
        _;
    }

    function addDaoMember(address _daoMember) external onlyDaoMember {
        daoMembers.push(_daoMember);
    }

    function removeDaoMember(address _daoMember) external onlyDaoMember {
        //        uint index = daoMembers.indexOf(_daoMember);
        //        daoMembers.remove(index);
    }

    function isDaoMember(address _daoMember) external view returns (bool) {
        //        return daoMembers.indexOf(_daoMember) >= 0;
        return false;
    }

    function getQuorum() public view returns (uint256) {
        uint256 n = getNodeOperatorsContract().getNodeOperatorsCount() * 2 / 3;
        return 1 + n;
    }

    // todo 重新设置 epochId  只要是operator成员就可以设置吗？  权限问题
    function resetExpectedEpochId() external onlyOwner {
        // 判断是否是白名单Operator
        // todo 权限是否冲突？
        //        require(getNodeOperatorsContract().isTrustedOperator(msg.sender), "Not part of DAOs' trusted list of addresses");
        expectedEpochId = _getFirstEpochOfDay(_getCurrentEpochId()) + EPOCHS_PER_FRAME;
    }

    function getLiquidStaking() public view returns (ILiquidStaking) {
        return ILiquidStaking(liquidStakingContract);
    }

    function getNodeOperatorsContract() public view returns (INodeOperatorsRegistry) {
        return INodeOperatorsRegistry(nodeOperatorsContract);
    }

    // getter
    //    function getExpectedEpochId() public view returns (uint256) {
    //        return expectedEpochId;
    //    }

    // todo 存在问题 一轮投票后 未满足quorum 需要清除一些基准数据：submittedReports hasSubmitted
    // todo 需要提供一种方式，让oracle获得 isReported
    // todo 可以添加一些 emit 供oracle进行订阅
    // todo 重新设置结构
    function reportBeacon(uint256 epochId, uint256 data, bytes32 nodeRankingCommitment) external {
        // todo 判断是否为dao成员的地址
        //        require(getNodeOperatorsContract().isTrusedOperator(msg.sender), "Not part of DAOs' trusted list of addresses");
        require(epochId == expectedEpochId, "The epoch submitted is not expected.");
        require(hasSubmitted[msg.sender] == false, "This msg.sender has already submitted the vote.");

        // 结果 hash 作为 k
        bytes32 hash = keccak256(abi.encode(data, nodeRankingCommitment));
        submittedReports[hash]++;

        hasSubmitted[msg.sender] = true;

        uint256 quorum = getQuorum();
        if (submittedReports[hash] > quorum) {
            pushReport(data, nodeRankingCommitment);
        }
    }

    // todo
    function pushReport(uint256 data, bytes32 nodeRankingCommitment) internal {
        ILiquidStaking liquidStaking = getLiquidStaking();
        liquidStaking.handleOracleReport(data, nodeRankingCommitment);
        uint256 nextExpectedEpoch = expectedEpochId + EPOCHS_PER_FRAME;
        // todo report后会重新设置 epochId  如果当天report失败了，那么想让epochId加一天 只能手动  resetExpectedEpochId
        expectedEpochId = nextExpectedEpoch;
    }

    // todo
    function verifyNftValue(bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID) external returns (bool){
        return false;
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

    function reportEncode(uint256 beaconBalances, uint32 beaconActiveValidators) internal returns (uint256) {
        return (beaconBalances << 64) | beaconActiveValidators;
    }

    function reportDecode(uint256 input) internal {
        beaconBalances = input >> 64;
        // todo
        //        beaconActiveValidators = input & 0xff;
    }

}
