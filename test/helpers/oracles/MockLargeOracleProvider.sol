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
        reportData.clBalance = 0;
        reportData.clVaultBalance = 0;
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
        bytes memory pubkey2 =
            bytes(hex"987ced126c2a2b49a862c3fed933310531568aeeb41b91d8dd571f363cf89783f1abdf4d41748bca9806807770980a12");
        bytes memory pubkey3 =
            bytes(hex"b80c2c5ea557296bfca760969afd2c3a22a8eeb27b651a2e7034a7a37ffdd2dd707275e8cfbeb372778ded3c6764f336");

        CLStakingExitInfo[] memory clStakingExitInfos = new CLStakingExitInfo[](1);
        bytes[] memory ps = new bytes[](3);
        ps[0] = pubkey;
        ps[1] = pubkey2;
        ps[2] = pubkey3;
        CLStakingExitInfo memory clStakingExitInfo = CLStakingExitInfo({stakingId: 1, pubkeys: ps});
        clStakingExitInfos[0] = clStakingExitInfo;
        reportData.clStakingExitInfos = clStakingExitInfos;

        CLStakingSlashInfo[] memory clStakingSlashInfos = new CLStakingSlashInfo[](3);
        CLStakingSlashInfo memory clStakingSlashInfo =
            CLStakingSlashInfo({stakingId: 1, slashAmount: 1 ether, pubkey: pubkey});
        CLStakingSlashInfo memory clStakingSlashInfo2 =
            CLStakingSlashInfo({stakingId: 1, slashAmount: 1 ether, pubkey: pubkey2});
        CLStakingSlashInfo memory clStakingSlashInfo3 =
            CLStakingSlashInfo({stakingId: 1, slashAmount: 1 ether, pubkey: pubkey3});
        clStakingSlashInfos[0] = clStakingSlashInfo;
        clStakingSlashInfos[1] = clStakingSlashInfo2;
        clStakingSlashInfos[2] = clStakingSlashInfo3;
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
