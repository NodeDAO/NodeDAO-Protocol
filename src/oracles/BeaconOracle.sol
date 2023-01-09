// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import "openzeppelin-contracts/utils/structs/EnumerableMap.sol";
import "src/interfaces/IBeaconOracle.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";

/**
  * @title Beacon Oracle and Dao
  *
  * BeaconOracle data acquisition and verification
  * Dao management
  */
contract BeaconOracle is
Initializable,
ReentrancyGuardUpgradeable,
OwnableUpgradeable,
UUPSUpgradeable,
IBeaconOracle
{
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // dao address
    address public dao;

    // oracle committee members
    mapping(address => bool) internal oracleMembers;

    uint32 public oracleMemberCount;

    // Number of slots corresponding to each epoch
    uint64 internal constant SLOTS_PER_EPOCH = 32;

    // Base time (default beacon creation time)
    uint64 public constant GENESIS_TIME = 1606824023;

    // Seconds for each slot
    uint64 internal constant SECONDS_PER_SLOT = 12;

    // The epoch of each frame (currently 24h for 225)
    uint32 public epochsPerFrame;

    // The expected epoch Id is required by oracle for report Beacon
    uint256 public expectedEpochId;

    // map(k:Upload the resulting hash v:The number of times you get the same result)
    EnumerableMap.Bytes32ToUintMap internal submittedReports;

    // map(k:oracleMember address v:is reportBeacon)
    EnumerableMap.AddressToUintMap internal hasSubmitted;

    // Whether the current frame has reached Quorum
    bool public isQuorum;

    // current reportBeacon beaconBalances
    uint256 public beaconBalances;

    // current reportBeacon beaconValidators
    uint64 public beaconActiveValidators;

    // reportBeacon merkleTreeRoot storage
    bytes32 private merkleTreeRoot;

    address public liquidStakingContract;

    address public nodeOperatorsContract;

    function initialize(address _dao, address _liquidStaking, address _nodeOperatorsContract) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        liquidStakingContract = _liquidStaking;
        nodeOperatorsContract = _nodeOperatorsContract;
        epochsPerFrame = 225;
        // So the initial is the first epochId
        expectedEpochId = _getFirstEpochOfDay(_getCurrentEpochId()) + epochsPerFrame;
    }

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    function addOracleMember(address _oracleMember) external onlyDao {
        oracleMembers[_oracleMember] = true;
        oracleMemberCount ++;

        emit AddOracleMember(_oracleMember);
    }

    function removeOracleMember(address _oracleMember) external onlyDao {
        delete oracleMembers[_oracleMember];
        oracleMemberCount --;

        emit RemoveOracleMember(_oracleMember);
    }

    function isOracleMember(address _oracleMember) external view returns (bool) {
        return _isOracleMember(_oracleMember);
    }

    function _isOracleMember(address _oracleMember) internal view returns (bool) {
        return oracleMembers[_oracleMember] == true;
    }

    // Example Reset the reporting frequency
    function resetEpochsPerFrame(uint32 _epochsPerFrame) external onlyDao {
        epochsPerFrame = _epochsPerFrame;

        emit ResetEpochsPerFrame(_epochsPerFrame);
    }

    // get Quorum
    // Quorum = operatorCount * 2 / 3 + 1
    function getQuorum() public view returns (uint32) {
        uint32 n = uint32(getNodeOperatorsContract().getNodeOperatorsCount()) * 2 / 3;
        return uint32(n + 1);
    }

    function getLiquidStaking() public view returns (ILiquidStaking) {
        return ILiquidStaking(liquidStakingContract);
    }

    function getNodeOperatorsContract() public view returns (INodeOperatorsRegistry) {
        return INodeOperatorsRegistry(nodeOperatorsContract);
    }

    function reportBeacon(uint256 _epochId, uint64 _beaconBalance, uint32 _beaconValidators, bytes32 _nodeRankingCommitment) external {
        require(isQuorum == false, "Quorum has been reached.");
        require(_isOracleMember(msg.sender), "Not part of DAOs' trusted list of addresses");
        require(_epochId == expectedEpochId, "The epoch submitted is not expected.");
        if (EnumerableMap.contains(hasSubmitted, msg.sender)) {
            require(EnumerableMap.get(hasSubmitted, msg.sender) == 0, "This msg.sender has already submitted the vote.");
        }

        bytes32 hash = keccak256(abi.encode(_beaconBalance, _beaconValidators, _nodeRankingCommitment));
        uint256 sameCount;
        if (EnumerableMap.contains(submittedReports, hash)) {
            sameCount = EnumerableMap.get(submittedReports, hash);
        }
        sameCount++;
        EnumerableMap.set(submittedReports, hash, sameCount);

        EnumerableMap.set(hasSubmitted, msg.sender, 1);
        emit ReportBeacon(_epochId, msg.sender, sameCount);

        uint32 quorum = getQuorum();
        //        uint32 quorum = 3;
        if (sameCount >= quorum) {
            _pushReport(_beaconBalance, _beaconValidators, _nodeRankingCommitment);
            emit ReportSuccess(_epochId, quorum, sameCount);
        }
    }

    function isReportBeacon() external view returns (bool) {
        if (EnumerableMap.contains(hasSubmitted, msg.sender)) {
            return EnumerableMap.get(hasSubmitted, msg.sender) == 1;
        }
        return false;
    }

    function _pushReport(uint64 _beaconBalance, uint32 _beaconValidators, bytes32 _nodeRankingCommitment) private {
        ILiquidStaking liquidStaking = getLiquidStaking();
        liquidStaking.handleOracleReport(_beaconBalance, _beaconValidators, _nodeRankingCommitment);
        uint256 nextExpectedEpoch = expectedEpochId + epochsPerFrame;

        expectedEpochId = nextExpectedEpoch;
        // The report passed on the same day
        isQuorum = true;
        beaconBalances = _beaconBalance;
        beaconActiveValidators = _beaconValidators;
        merkleTreeRoot = _nodeRankingCommitment;

        // clear map
        _clearReportedMap();
    }

    function _clearReportedMap() private {
        bytes32[] memory submittedReportKeys = EnumerableMap.keys(submittedReports);
        uint256 submittedLen = submittedReportKeys.length;
        if (submittedLen > 0) {
            for (uint256 i = 0; i < submittedLen; i++) {
                EnumerableMap.remove(submittedReports, submittedReportKeys[i]);
            }
        }

        address[] memory hasSubmittedKeys = EnumerableMap.keys(hasSubmitted);
        uint256 hasSubmittedLen = hasSubmittedKeys.length;
        if (hasSubmittedLen > 0) {
            for (uint256 i = 0; i < hasSubmittedLen; i++) {
                EnumerableMap.remove(hasSubmitted, hasSubmittedKeys[i]);
            }
        }
    }

    // leaf: bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID
    function verifyNftValue(
        bytes32[] memory proof,
        bytes memory pubkey,
        uint256 validatorBalance,
        uint256 nftTokenID
    ) external view returns (bool){
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(pubkey, validatorBalance, nftTokenID))));
        return MerkleProof.verify(proof, merkleTreeRoot, leaf);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _getFirstEpochOfDay(uint256 _epochId) internal view returns (uint256) {
        return (_epochId / epochsPerFrame) * epochsPerFrame;
    }

    function _getCurrentEpochId() internal view returns (uint256) {
        // The number of epochs after the base time
        return (_getTime() - GENESIS_TIME) / (SLOTS_PER_EPOCH * SECONDS_PER_SLOT);
    }

    function _getTime() internal view returns (uint256) {
        return block.timestamp;
    }

}
