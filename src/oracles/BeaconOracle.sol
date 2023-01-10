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

    // Use the maximum value of uint256 as the index that does not exist
    uint256 internal constant MEMBER_NOT_FOUND = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// The bitmask of the oracle members that pushed their reports
    // keccak256("oracle.reportsBitMask")
    uint256 internal reportBitMaskPosition = 0xc25c9b62b6d0f24f0d2ed8730d23f158f481aba9a9521a1d67014c7fa19a1ccd;

    // Number of slots corresponding to each epoch
    uint64 internal constant SLOTS_PER_EPOCH = 32;

    // Base time (default beacon creation time)
    uint64 public constant GENESIS_TIME = 1606824023;

    // Seconds for each slot
    uint64 internal constant SECONDS_PER_SLOT = 12;

    // dao address
    address public dao;

    // oracle committee members
    address[] private oracleMembers;

    // Maximum number of oracle committee members
    uint256 public constant MAX_MEMBERS = 256;

    // The epoch of each frame (currently 24h for 225)
    uint32 public epochsPerFrame;

    // The expected epoch Id is required by oracle for report Beacon
    uint256 public expectedEpochId;

    // Whether the current frame has reached Quorum
    bool public isQuorum;

    // current reportBeacon beaconBalances
    uint128 public beaconBalances;

    // current reportBeacon beaconValidators
    uint64 public beaconActiveValidators;

    // reportBeacon merkleTreeRoot storage
    bytes32 private merkleTreeRoot;

    bytes32[] private currentReportVariants;

    address public nodeOperatorsContract;

    function initialize(address _dao, address _nodeOperatorsContract) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        nodeOperatorsContract = _nodeOperatorsContract;
        epochsPerFrame = 225;
        // So the initial is the first epochId
        expectedEpochId = _getFrameFirstEpochOfDay(_getCurrentEpochId()) + epochsPerFrame;
    }

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    function addOracleMember(address _oracleMember) external onlyDao {
        require(address(0) != _oracleMember, "BAD_ARGUMENT");
        require(oracleMembers.length < MAX_MEMBERS, "TOO_MANY_MEMBERS");
        require(MEMBER_NOT_FOUND == _getMemberId(_oracleMember), "MEMBER_EXISTS");

        oracleMembers.push(_oracleMember);

        emit AddOracleMember(_oracleMember);
    }

    function removeOracleMember(address _oracleMember) external onlyDao {
        uint256 index = _getMemberId(_oracleMember);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");

        delete oracleMembers[index];

        emit RemoveOracleMember(_oracleMember);
    }

    function isOracleMember(address _oracleMember) external view returns (bool) {
        return _isOracleMember(_oracleMember);
    }

    function _isOracleMember(address _oracleMember) internal view returns (bool) {
        uint256 index = _getMemberId(_oracleMember);
        return index != MEMBER_NOT_FOUND;
    }

    // Example Reset the reporting frequency
    function resetEpochsPerFrame(uint32 _epochsPerFrame) external onlyDao {
        epochsPerFrame = _epochsPerFrame;

        emit ResetEpochsPerFrame(_epochsPerFrame);
    }

    /**
     * description: get Quorum
     * @return {uint32} Quorum = operatorCount * 2 / 3 + 1
     */
    function getQuorum() public view returns (uint32) {
        uint32 n = (uint32(getNodeOperatorsContract().getNodeOperatorsCount()) * 2) / 3;
        return uint32(n + 1);
    }

    function getNodeOperatorsContract() public view returns (INodeOperatorsRegistry) {
        return INodeOperatorsRegistry(nodeOperatorsContract);
    }

    /**
     * description: The oracle service reports beacon chain data to the contract
     * @param _epochId The epoch Id expected by the current frame
     * @param _beaconBalance Beacon chain balance
     * @param _beaconValidators Number of beacon chain validators
     * @param _commitNonce 提交时stake pool对应的nonce
     * @param _nodeRankingCommitment merkle root
     */
    function reportBeacon(
        uint256 _epochId,
        uint128 _beaconBalance,
        uint32 _beaconValidators,
        uint256 _commitNonce,
        bytes32 _nodeRankingCommitment
    ) external {
        if (isQuorum) {
            emit achieveQuorum(_epochId, isQuorum, getQuorum());
            return;
        }
        // make sure the oracle is from members list and has not yet voted
        uint256 index = _getMemberId(msg.sender);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");

        uint256 bitMask = reportBitMaskPosition;
        uint256 mask = 1 << index;
        require(bitMask & mask == 0, "ALREADY_SUBMITTED");
        // reported, set the bitmask to the specified bit
        reportBitMaskPosition = bitMask | mask;

        require(_epochId == expectedEpochId, "The epoch submitted is not expected.");
        // if (EnumerableMap.contains(hasSubmitted, msg.sender)) {
        //     require(EnumerableMap.get(hasSubmitted, msg.sender) == 0, "This msg.sender has already submitted the vote.");
        // }

        // bytes32 hash = keccak256(abi.encode(_beaconBalance, _beaconValidators, _nodeRankingCommitment));
        // uint32 sameCount;
        // if (EnumerableMap.contains(submittedReports, hash)) {
        //     sameCount = uint32(EnumerableMap.get(submittedReports, hash));
        // }
        // sameCount++;
        // EnumerableMap.set(submittedReports, hash, sameCount);

        // EnumerableMap.set(hasSubmitted, msg.sender, 1);
        // emit ReportBeacon(_epochId, msg.sender, sameCount);

        // uint32 quorum = getQuorum();
        // if (sameCount >= quorum) {
        //     _pushReport(_beaconBalance, _beaconValidators, _nodeRankingCommitment);
        //     emit ReportSuccess(_epochId, quorum, sameCount);
        // }
    }

    function isReportBeacon() external view returns (bool) {
        // if (EnumerableMap.contains(hasSubmitted, msg.sender)) {
        //     return EnumerableMap.get(hasSubmitted, msg.sender) == 1;
        // }
        return false;
    }

    function _pushReport(uint64 _beaconBalance, uint32 _beaconValidators, bytes32 _nodeRankingCommitment) private {
        // ILiquidStaking liquidStaking = getLiquidStaking();
        // liquidStaking.handleOracleReport(_beaconBalance, _beaconValidators);
        uint256 nextExpectedEpoch = expectedEpochId + epochsPerFrame;

        expectedEpochId = nextExpectedEpoch;
        // The report passed on the same day
        isQuorum = true;
        beaconBalances = _beaconBalance;
        beaconActiveValidators = _beaconValidators;
        merkleTreeRoot = _nodeRankingCommitment;

        // clear map
        // _clearReportedMap();
    }

    // function _clearReportedMap() private {
    //     bytes32[] memory submittedReportKeys = EnumerableMap.keys(submittedReports);
    //     uint256 submittedLen = submittedReportKeys.length;
    //     if (submittedLen > 0) {
    //         for (uint256 i = 0; i < submittedLen; i++) {
    //             EnumerableMap.remove(submittedReports, submittedReportKeys[i]);
    //         }
    //     }

    //     address[] memory hasSubmittedKeys = EnumerableMap.keys(hasSubmitted);
    //     uint256 hasSubmittedLen = hasSubmittedKeys.length;
    //     if (hasSubmittedLen > 0) {
    //         for (uint256 i = 0; i < hasSubmittedLen; i++) {
    //             EnumerableMap.remove(hasSubmitted, hasSubmittedKeys[i]);
    //         }
    //     }
    // }

    /**
     * description: Verify the value of nft
     * leaf: bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID
     * @return {bool} Whether the verification is successful
     */
    function verifyNftValue(bytes32[] memory proof, bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID)
        external
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(pubkey, validatorBalance, nftTokenID))));
        return MerkleProof.verify(proof, merkleTreeRoot, leaf);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Return `_member` index in the members list or MEMBER_NOT_FOUND
     */
    function _getMemberId(address _member) internal view returns (uint256) {
        uint256 length = oracleMembers.length;
        for (uint256 i = 0; i < length; ++i) {
            if (oracleMembers[i] == _member) {
                return i;
            }
        }
        return MEMBER_NOT_FOUND;
    }

    /**
     * description: Return the first epoch of the frame that `_epochId` belongs to
     */
    function _getFrameFirstEpochOfDay(uint256 _epochId) internal view returns (uint256) {
        return (_epochId / epochsPerFrame) * epochsPerFrame;
    }

    /**
     * description: Return the epoch calculated from current timestamp
     */
    function _getCurrentEpochId() internal view returns (uint256) {
        // The number of epochs after the base time
        return (_getTime() - GENESIS_TIME) / (SLOTS_PER_EPOCH * SECONDS_PER_SLOT);
    }

    /**
     * description Return the current timestamp
     */
    function _getTime() internal view returns (uint256) {
        return block.timestamp;
    }
}
