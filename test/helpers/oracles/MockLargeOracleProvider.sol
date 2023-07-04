// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "test/helpers/oracles/MockMultiOracleProvider.sol";
import "src/oracles/WithdrawOracle.sol";
import "src/oracles/LargeStakeOracle.sol";
import {CLStakingExitInfo, CLStakingSlashInfo} from "src/library/ConsensusStruct.sol";

// Provide baseline data for the Hash Consensus contract test
contract MockLargeOracleProvider is MockMultiOracleProvider {
    function mockWithdrawOracleNoExitReportData(uint256 refSlot)
        public
        pure
        returns (WithdrawOracle.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 607910611984000000000;
        reportData.clVaultBalance = 1453040740000000000;
        reportData.clSettleAmount = 0;
        reportData.reportExitedCount = 0;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](0);
        reportData.withdrawInfos = withdrawInfos;

        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](0);
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockLargeStakeOracleEmptyReportData(uint256 refSlot)
        public
        pure
        returns (LargeStakeOracle.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;

        CLStakingExitInfo[] memory clStakingExitInfos = new CLStakingExitInfo[](0);
        reportData.clStakingExitInfos = clStakingExitInfos;

        CLStakingSlashInfo[] memory clStakingSlashInfos = new CLStakingSlashInfo[](0);
        reportData.clStakingSlashInfos = clStakingSlashInfos;
    }

    function mockLargeStakeOracleEmptyReportDataHash(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash1 = keccak256(abi.encode(mockWithdrawOracleNoExitReportData(refSlot)));
        bytes32 hash2 = keccak256(abi.encode(mockLargeStakeOracleEmptyReportData(refSlot)));
        hashArr[0] = hash1;
        hashArr[1] = hash2;
        return hashArr;
    }

    function mockLargeStakeOracleReportDataExitAndSlash(uint256 refSlot)
        public
        pure
        returns (LargeStakeOracle.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;

        bytes memory pubkey =
            bytes(hex"92a14b12a4231e94507f969e367f6ee0eaf93a9ba3b82e8ab2598c8e36f3cd932d5a446a528bf3df636ed8bb3d1cfde9");

        CLStakingExitInfo[] memory clStakingExitInfos = new CLStakingExitInfo[](1);
        CLStakingExitInfo memory clStakingExitInfo = CLStakingExitInfo({stakingId: 1, pubkey: pubkey});
        clStakingExitInfos[0] = clStakingExitInfo;
        reportData.clStakingExitInfos = clStakingExitInfos;

        CLStakingSlashInfo[] memory clStakingSlashInfos = new CLStakingSlashInfo[](1);
        CLStakingSlashInfo memory clStakingSlashInfo =
            CLStakingSlashInfo({stakingId: 1, slashAmount: 32 ether, pubkey: pubkey});
        clStakingSlashInfos[0] = clStakingSlashInfo;
        reportData.clStakingSlashInfos = clStakingSlashInfos;
    }

    function mockLargeStakeOracleReportDataExitAndSlashHash(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash1 = keccak256(abi.encode(mockWithdrawOracleNoExitReportData(refSlot)));
        bytes32 hash2 = keccak256(abi.encode(mockLargeStakeOracleReportDataExitAndSlash(refSlot)));
        hashArr[0] = hash1;
        hashArr[1] = hash2;
        return hashArr;
    }
}
