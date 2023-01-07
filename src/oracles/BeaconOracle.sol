// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
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
    using MerkleProof for uint256;

    // dao address
    address public dao;

    // oracle committee members
    mapping(address => bool) internal oracleMembers;

    // Number of slots corresponding to each epoch
    uint64 internal constant SLOTS_PER_EPOCH = 32;

    // Base time (default beacon creation time)
    uint64 internal constant GENESIS_TIME = 1606824023;

    // Seconds for each slot
    uint64 internal constant SECONDS_PER_SLOT = 12;

    // The epoch of each frame (currently 24h for 225)
    uint32 public epochsPerFrame;

    // The expected epoch Id is required by oracle for report Beacon
    uint256 public expectedEpochId;

    // map(k:epochId v(k:Upload the resulting hash v:The number of times you get the same result))
    mapping(uint256 => mapping(bytes32 => uint256)) internal submittedReports;

    // map(k:epochId v(k:oracleMember address v:is reportBeacon))
    mapping(uint256 => mapping(address => bool)) internal hasSubmitted;

    // reporting storage
//    uint256[] private currentReportVariants;

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

    function initalizeOracle(address _liquidStaking, address _nodeOperatorsContract, address[] memory _oracleMembers) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        liquidStakingContract = _liquidStaking;
        nodeOperatorsContract = _nodeOperatorsContract;
        _initOracleMembers(_oracleMembers);
        epochsPerFrame = 225;
        // So the initial is the first epochId
        expectedEpochId = _getFirstEpochOfDay(_getCurrentEpochId()) + epochsPerFrame;
    }

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    function _initOracleMembers(address[] memory _oracleMembers) internal {
        for (uint i = 0; i < _oracleMembers.length; i++) {
            oracleMembers[_oracleMembers[i]] = true;
        }
    }

    function addOracleMember(address _oracleMember) external onlyDao {
        oracleMembers[_oracleMember] = true;
    }

    function removeOracleMember(address _oracleMember) external onlyDao {
        delete oracleMembers[_oracleMember];
    }

    function isOracleMember(address _oracleMember) external view returns (bool) {
        return _isOracleMember(_oracleMember);
    }

    function _isOracleMember(address _oracleMember) internal view returns (bool) {
        return oracleMembers[_oracleMember];
    }

    function resetExpectedEpochId() external onlyDao {
        expectedEpochId = _getFirstEpochOfDay(_getCurrentEpochId()) + epochsPerFrame;
    }

    function resetEpochsPerFrame(uint32 _epochsPerFrame) external onlyDao {
        epochsPerFrame = _epochsPerFrame;
    }

    function getQuorum() public view returns (uint256) {
        uint256 n = getNodeOperatorsContract().getNodeOperatorsCount() * 2 / 3;
        return 1 + n;
    }

    function getLiquidStaking() public view returns (ILiquidStaking) {
        return ILiquidStaking(liquidStakingContract);
    }

    function getNodeOperatorsContract() public view returns (INodeOperatorsRegistry) {
        return INodeOperatorsRegistry(nodeOperatorsContract);
    }

    function reportBeacon(uint256 _epochId, uint64 _beaconBalance, uint32 _beaconValidators, bytes32 _nodeRankingCommitment) external {
        require(isQuorum, "Quorum has been reached.");
        require(_isOracleMember(msg.sender), "Not part of DAOs' trusted list of addresses");
        require(_epochId == expectedEpochId, "The epoch submitted is not expected.");
        require(hasSubmitted[_epochId][msg.sender], "This msg.sender has already submitted the vote.");

        bytes32 hash = keccak256(abi.encode(_beaconBalance, _beaconValidators, _nodeRankingCommitment));
        submittedReports[_epochId][hash]++;
        hasSubmitted[_epochId][msg.sender] = true;

        uint256 quorum = getQuorum();
        if (submittedReports[_epochId][hash] > quorum) {
            _pushReport(_beaconBalance, _beaconValidators, _nodeRankingCommitment);
        }
    }

    function isReportBeacon(uint256 _epochId) external view returns (bool) {
        return hasSubmitted[_epochId][msg.sender] == true;
    }

    function _pushReport(uint64 _beaconBalance, uint32 _beaconValidators, bytes32 _nodeRankingCommitment) internal {
        ILiquidStaking liquidStaking = getLiquidStaking();
        liquidStaking.handleOracleReport(_beaconBalance, _beaconValidators, _nodeRankingCommitment);
        uint256 nextExpectedEpoch = expectedEpochId + epochsPerFrame;

        expectedEpochId = nextExpectedEpoch;
        // The report passed on the same day
        isQuorum = true;

        // todo no delete
        //        delete submittedReports[_epochId];
        //        delete hasSubmitted[_epochId];
    }

    // byte32 memory pubkey, uint64 validatorBalance, uint256 nftTokenID
    function verifyNftValue(bytes32[] memory proof, bytes32 leaf) external view returns (bool){
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
