// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

/**
 * @title Beacon Oracle and Dao
 *
 * BeaconOracle data acquisition and verification
 * Dao management
 */
interface IBeaconOracle {
    /**
     * Verify the value of nft
     * leaf: bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID
     * @param {bytes32[] memory} proof validator's merkleTree proof
     * @param {bytes memory} pubkey
     * @param {uint256} beaconBalance validator consensus layer balance
     * @param {uint256} nftTokenID
     * @return whether the validation passed
     */
    function verifyNftValue(bytes32[] memory proof, bytes memory pubkey, uint256 validatorBalance, uint256 nftTokenID)
        external
        view
        returns (bool);

    /**
     * @return {bool} is oracleMember
     */
    function isOracleMember(address oracleMember) external view returns (bool);

    /**
     * Add oracle member
     */
    function addOracleMember(address _oracleMember) external;

    /**
     * Add oracle member and configure all members to re-report
     */
    function removeOracleMember(address _oracleMember) external;

    /**
     * @return {uint128} The total balance of the consensus layer
     */
    function getBeaconBalances() external view returns (uint256);

    /**
     * @return {uint128} The total balance of the pending validators
     */
    function getPendingBalances() external view returns (uint256);
    /**
     * @return {uint128} The total validator count of the consensus layer
     */
    function getBeaconValidators() external view returns (uint256);

    /**
     * @notice add pending validator value
     */
    function addPendingBalances(uint256 _pendingBalance) external;

    event AddOracleMember(address oracleMember);
    event RemoveOracleMember(address oracleMember);
    event ResetExpectedEpochId(uint256 expectedEpochId);
    event ExpectedEpochIdUpdated(uint256 expectedEpochId);
    event ResetEpochsPerFrame(uint256 epochsPerFrame);
    event ReportBeacon(
        uint256 epochId,
        address oracleMember,
        uint32 sameReportCount,
        uint256 _beaconBalance,
        uint256 _beaconValidators,
        bytes32 _validatorRankingRoot
    );
    event ReportSuccess(
        uint256 epochId,
        uint256 sameReportCount,
        uint32 quorum,
        uint256 _beaconBalance,
        uint256 _beaconValidators,
        bytes32 _validatorRankingRoot
    );
    event PendingBalancesAdd(uint256 addBalance, uint256 totalBalance);
    event PendingBalancesReset(uint256 totalBalance);
    event LiquidStakingChanged(address _before, address _after);
}
