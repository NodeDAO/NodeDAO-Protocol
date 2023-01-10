// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import "src/interfaces/IBeaconOracle.sol";
import "src/oracles/ReportUtils.sol";

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
    using ReportUtils for bytes;

    // Use the maximum value of uint256 as the index that does not exist
    uint256 internal constant MEMBER_NOT_FOUND = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// The bitmask of the oracle members that pushed their reports
    // keccak256("oracle.reportsBitMask")
    // uint256 internal reportBitMaskPosition = 0xea6fa022365e4737a3bb52facb00ddc693a656fb51ffb2b4bd24fb85bdc888be;
    uint256 internal reportBitMaskPosition = 0;

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
    uint64 public beaconValidators;

    // reportBeacon merkleTreeRoot storage
    bytes32 private merkleTreeRoot;

    bytes[] private currentReportVariants;

    function initialize(address _dao) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        epochsPerFrame = 225;
        // So the initial is the first epochId
        expectedEpochId = _getFrameFirstEpochOfDay(_getCurrentEpochId());
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

    function getBeaconBalances() external view returns (uint128) {
        return beaconBalances;
    }

    function getBeaconValidators() external view returns (uint64) {
        return beaconValidators;
    }

    /**
     * description: get Quorum
     * @return {uint32} Quorum = operatorCount * 2 / 3 + 1
     */
    function getQuorum() public view returns (uint32) {
        uint32 n = (uint32(oracleMembers.length) * 2) / 3;
        return uint32(n + 1);
    }

    /**
     * description: The oracle service reports beacon chain data to the contract
     * @param _epochId The epoch Id expected by the current frame
     * @param _beaconBalance Beacon chain balance
     * @param _beaconValidators Number of beacon chain validators
     * @param _validatorRankingRoot merkle root
     */
    function reportBeacon(
        uint256 _epochId,
        uint128 _beaconBalance,
        uint32 _beaconValidators,
        bytes32 _validatorRankingRoot
    ) external {
        if (isQuorum) {
            emit achieveQuorum(_epochId, isQuorum, getQuorum());
            return;
        }
        require(_epochId >= expectedEpochId, "EPOCH_IS_TOO_OLD");

        // if expected epoch has advanced, check that this is the first epoch of the current frame
        // and clear the last unsuccessful reporting
        if (_epochId > expectedEpochId) {
            require(_epochId == _getFrameFirstEpochOfDay(_getCurrentEpochId()), "UNEXPECTED_EPOCH");
            _clearReportingAndAdvanceTo(_epochId);
        }

        // make sure the oracle is from members list and has not yet voted
        uint256 index = _getMemberId(msg.sender);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");

        uint256 bitMask = reportBitMaskPosition;
        uint256 mask = 1 << index;
        require(bitMask & mask == 0, "ALREADY_SUBMITTED");
        // reported, set the bitmask to the specified bit
        reportBitMaskPosition = bitMask | mask;

        // push this report to the matching kind
        uint256 quorum = getQuorum();

        uint256 i = 0;
        uint16 sameCount;
        uint256 nextEpochId = _epochId + epochsPerFrame;

        // iterate on all report variants we already have, limited by the oracle members maximum
        while (i < currentReportVariants.length) {
            (bool isDifferent, uint16 count) = ReportUtils.isReportDifferentAndCount(
                currentReportVariants[i], _validatorRankingRoot, _beaconBalance, _beaconValidators
            );

            if (isDifferent) {
                ++i;
            } else {
                sameCount = count;
                break;
            }
        }

        emit ReportBeacon(_epochId, msg.sender, sameCount + 1);

        if (i < currentReportVariants.length) {
            if (sameCount + 1 >= quorum) {
                _dealReport(nextEpochId, _beaconBalance, _beaconValidators, _validatorRankingRoot);
                emit ReportSuccess(_epochId, quorum, sameCount);
            } else {
                // increment report counter, see ReportUtils for details
                currentReportVariants[i] = ReportUtils.compressReportData(
                    _validatorRankingRoot, _beaconBalance, _beaconValidators, sameCount + 1
                );
            }
        } else {
            if (quorum == 1) {
                _dealReport(nextEpochId, _beaconBalance, _beaconValidators, _validatorRankingRoot);
                emit ReportSuccess(_epochId, quorum, sameCount);
            } else {
                currentReportVariants.push(
                    ReportUtils.compressReportData(
                        _validatorRankingRoot, _beaconBalance, _beaconValidators, sameCount + 1
                    )
                );
            }
        }

    }

    function isReportBeacon() external view returns (bool) {
        // make sure the oracle is from members list and has not yet voted
        uint256 index = _getMemberId(msg.sender);
        if (index == MEMBER_NOT_FOUND) return false;
        uint256 bitMask = reportBitMaskPosition;
        uint256 mask = 1 << index;
        return bitMask & mask != 0;
    }

    /**
     * report reaches quorum processing data
     * param {uint256} _nextExpectedEpochId The next expected epochId
     */
    function _dealReport(
        uint256 _nextExpectedEpochId,
        uint128 _beaconBalance,
        uint32 _beaconValidators,
        bytes32 _validatorRankingRoot
    ) internal {
        // The report passed on the same day
        isQuorum = true;
        beaconBalances = _beaconBalance;
        beaconValidators = _beaconValidators;
        merkleTreeRoot = _validatorRankingRoot;

        // clear report array
        _clearReportingAndAdvanceTo(_nextExpectedEpochId);
    }

    /**
     *  Remove the current reporting progress and advances to accept the later epoch `_epochId`
     */
    function _clearReportingAndAdvanceTo(uint256 _nextExpectedEpochId) internal {
        reportBitMaskPosition = 0;
        expectedEpochId = _nextExpectedEpochId;

        delete currentReportVariants;
        emit ExpectedEpochIdUpdated(_nextExpectedEpochId);
    }

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
