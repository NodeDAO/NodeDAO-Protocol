// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

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

    // Number of slots corresponding to each epoch
    uint64 internal constant SLOTS_PER_EPOCH = 32;

    // Seconds for each slot
    uint64 internal constant SECONDS_PER_SLOT = 12;

    /// The bitmask of the oracle members that pushed their reports (default:0)
    uint256 internal reportBitMaskPosition;

    // dao address
    address public dao;

    // Base time (default beacon creation time)
    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 public genesisTime;

    // The epoch of each frame (currently 24h for 225)
    uint32 public epochsPerFrame;

    // The expected epoch Id is required by oracle for report Beacon
    uint256 public expectedEpochId;

    // current reportBeacon beaconBalances
    uint128 public beaconBalances;

    // current reportBeacon beaconValidators
    uint64 public beaconValidators;

    uint256 public oracleMemberCount;

    // reportBeacon merkleTreeRoot storage
    bytes32 internal merkleTreeRoot;

    // reportBeacon storge
    bytes[] internal currentReportVariants;

    // oracle commit members
    address[] internal oracleMembers;

    function initialize(address _dao, uint64 _genesisTime) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        genesisTime = _genesisTime;
        epochsPerFrame = 225;
        // So the initial is the first epochId
        expectedEpochId = _getFrameFirstEpochOfDay(getCurrentEpochId());
    }

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    /**
     * description: get Quorum
     * @return {uint32} Quorum = oracleMemberCount * 2 / 3 + 1
     */
    function getQuorum() public view returns (uint256) {
        uint256 n = (oracleMemberCount * 2) / 3;
        return n + 1;
    }

    /**
     * Return the epoch calculated from current timestamp
     */
    function getCurrentEpochId() public view returns (uint256) {
        // The number of epochs after the base time
        return (_getTime() - genesisTime) / (SLOTS_PER_EPOCH * SECONDS_PER_SLOT);
    }

    /**
     * Whether it's in the middle of the voting cycle
     */
    function isCurrentFrame() public view returns (bool) {
        return getCurrentEpochId() >= expectedEpochId;
    }

    /**
     * Return `_member` index in the members list or MEMBER_NOT_FOUND
     */
    function getMemberId(address _member) public view returns (uint256) {
        uint256 length = oracleMembers.length;
        for (uint256 i = 0; i < length; ++i) {
            if (oracleMembers[i] == _member) {
                return i;
            }
        }
        return MEMBER_NOT_FOUND;
    }

    /**
     * set dao vault address
     */
    function setDaoAddress(address _dao) external onlyDao {
        dao = _dao;
    }

    /**
     * Add oracle member
     */
    function addOracleMember(address _oracleMember) external onlyDao {
        require(address(0) != _oracleMember, "BAD_ARGUMENT");
        require(MEMBER_NOT_FOUND == getMemberId(_oracleMember), "MEMBER_EXISTS");

        bool isAdd = false;
        for (uint256 i = 0; i < oracleMembers.length; ++i) {
            if (oracleMembers[i] == address(0)) {
                oracleMembers[i] = _oracleMember;
                isAdd = true;
                break;
            }
        }

        if (!isAdd) {
            oracleMembers.push(_oracleMember);
        }

        oracleMemberCount++;

        emit AddOracleMember(_oracleMember);
    }

    /**
     * Add oracle member and configure all members to re-report
     */
    function removeOracleMember(address _oracleMember) external onlyDao {
        require(address(0) != _oracleMember, "BAD_ARGUMENT");
        uint256 index = getMemberId(_oracleMember);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");
        require(oracleMemberCount > 0, "Member count is 0");
        delete oracleMembers[index];
        oracleMemberCount--;

        emit RemoveOracleMember(_oracleMember);

        // There is an operation to delete oracleMember, all members need to report again
        reportBitMaskPosition = 0;
        delete currentReportVariants;
    }

    /**
     * @return {bool} is oracleMember
     */
    function isOracleMember(address _oracleMember) external view returns (bool) {
        require(address(0) != _oracleMember, "BAD_ARGUMENT");
        return _isOracleMember(_oracleMember);
    }

    /**
     * Example Reset the reporting frequency
     */
    function resetEpochsPerFrame(uint32 _epochsPerFrame) external onlyDao {
        epochsPerFrame = _epochsPerFrame;

        emit ResetEpochsPerFrame(_epochsPerFrame);
    }

    /**
     * @return {uint128} The total balance of the consensus layer
     */
    function getBeaconBalances() external view returns (uint128) {
        return beaconBalances;
    }

    /**
     * @return {uint128} The total validator count of the consensus layer
     */
    function getBeaconValidators() external view returns (uint64) {
        return beaconValidators;
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
        require(getCurrentEpochId() >= expectedEpochId, "EPOCH_IS_NOT_CURRENT_FRAME");
        require(_epochId >= expectedEpochId, "EPOCH_IS_TOO_OLD");

        // if expected epoch has advanced, check that this is the first epoch of the current frame
        // and clear the last unsuccessful reporting
        if (_epochId > expectedEpochId) {
            require(_epochId == _getFrameFirstEpochOfDay(getCurrentEpochId()), "UNEXPECTED_EPOCH");
            _clearReportingAndAdvanceTo(_epochId);
        }

        // make sure the oracle is from members list and has not yet voted
        uint256 index = getMemberId(msg.sender);
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
                emit ReportSuccess(_epochId, quorum, sameCount + 1);
            } else {
                // increment report counter, see ReportUtils for details
                currentReportVariants[i] = ReportUtils.compressReportData(
                    _validatorRankingRoot, _beaconBalance, _beaconValidators, sameCount + 1
                );
            }
        } else {
            if (quorum == 1) {
                _dealReport(nextEpochId, _beaconBalance, _beaconValidators, _validatorRankingRoot);
                emit ReportSuccess(_epochId, quorum, sameCount + 1);
            } else {
                currentReportVariants.push(
                    ReportUtils.compressReportData(
                        _validatorRankingRoot, _beaconBalance, _beaconValidators, sameCount + 1
                    )
                );
            }
        }
    }

    /**
     * Whether the address of the caller has performed reportBeacon
     */
    function isReportBeacon(address _oracleMember) external view returns (bool) {
        require(_oracleMember != address(0), "address provided invalid");
        // make sure the oracle is from members list and has not yet voted
        uint256 index = getMemberId(_oracleMember);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");
        uint256 bitMask = reportBitMaskPosition;
        uint256 mask = 1 << index;
        return bitMask & mask != 0;
    }

    /**
     * Verify the value of nft
     * leaf: bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID
     * @param {bytes32[] memory} proof validator's merkleTree proof
     * @param {bytes memory} pubkey
     * @param {uint256} beaconBalance validator consensus layer balance
     * @param {uint256} nftTokenID
     * @return whether the validation passed
     */
    function verifyNftValue(bytes32[] memory proof, bytes memory pubkey, uint256 beaconBalance, uint256 nftTokenID)
        external
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(pubkey, beaconBalance, nftTokenID))));
        return MerkleProof.verify(proof, merkleTreeRoot, leaf);
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
     * report reaches quorum processing data
     * param {uint256} _nextExpectedEpochId The next expected epochId
     */
    function _dealReport(
        uint256 _nextExpectedEpochId,
        uint128 _beaconBalance,
        uint32 _beaconValidators,
        bytes32 _validatorRankingRoot
    ) internal {
        beaconBalances = _beaconBalance;
        beaconValidators = _beaconValidators;
        merkleTreeRoot = _validatorRankingRoot;

        // clear report array
        _clearReportingAndAdvanceTo(_nextExpectedEpochId);
    }

    function _isOracleMember(address _oracleMember) internal view returns (bool) {
        uint256 index = getMemberId(_oracleMember);
        return index != MEMBER_NOT_FOUND;
    }

    /**
     * Return the first epoch of the frame that `_epochId` belongs to
     */
    function _getFrameFirstEpochOfDay(uint256 _epochId) internal view returns (uint256) {
        return (_epochId / epochsPerFrame) * epochsPerFrame;
    }

    /**
     * Return the current timestamp
     */
    function _getTime() internal view returns (uint256) {
        return block.timestamp;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
