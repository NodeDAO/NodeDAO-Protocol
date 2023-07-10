// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "test/helpers/oracles/MultiHashConsensusWithTimer.sol";
import "test/helpers/oracles/MockMultiReportProcessor.sol";
import "test/helpers/CommonConstantProvider.sol";
import {MockWithdrawInfo, WithdrawOracleWithTimer} from "test/helpers/oracles/WithdrawOracleWithTimer.sol";
import {WithdrawInfo, ExitValidatorInfo} from "src/library/ConsensusStruct.sol";
import "src/oracles/LargeStakeOracle.sol";
import "src/oracles/WithdrawOracle.sol";

// Provide baseline data for the Hash Consensus contract test
contract MockMultiOracleProvider is CommonConstantProvider {
    uint256 public constant SLOTS_PER_EPOCH = 32;
    uint256 public constant SECONDS_PER_SLOT = 12;
    // goerli: 1616508000
    // mainnet: 1606824023
    uint256 public constant GENESIS_TIME = 1616508000;
    uint256 public constant EPOCHS_PER_FRAME = 20;
    uint256 public constant INITIAL_EPOCH = 1;
    uint256 public constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;

    uint256 public constant SECONDS_PER_EPOCH = SLOTS_PER_EPOCH * SECONDS_PER_SLOT;
    uint256 public constant SECONDS_PER_FRAME = SECONDS_PER_EPOCH * EPOCHS_PER_FRAME;
    uint256 public constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;

    uint256 public constant CONSENSUS_VERSION = 2;

    uint256 public constant WITHDRAW_ORACLE_CONTRACT_VERSION = 2;
    uint256 public constant LARGE_STAKE_ORACLE_CONTRACT_VERSION = 1;

    address public constant MEMBER_1 = address(11);
    address public constant MEMBER_2 = address(12);
    address public constant MEMBER_3 = address(13);
    address public constant MEMBER_4 = address(14);
    address public constant MEMBER_5 = address(15);

    uint256 public constant DATA_FORMAT_LIST = 1;
    uint256 public constant LAST_PROCESSING_REF_SLOT = 1;
    uint256 public constant EXIT_REQUEST_LIMIT = 1000;
    uint256 public constant CL_VAULT_MIN_SETTLE_LIMIT = 1e19;

    uint256 public constant CL_BALANCE = 0;
    uint256 public constant PENDING_BALANCE = 0;

    function computeTimestampAtEpoch(uint256 _epoch) public pure returns (uint256) {
        return GENESIS_TIME + _epoch * SECONDS_PER_EPOCH;
    }

    function computeTimestampAtSlot(uint256 _slot) public pure returns (uint256) {
        return GENESIS_TIME + _slot * SECONDS_PER_SLOT;
    }

    function computeEpochFirstSlot(uint256 _epoch) public pure returns (uint256) {
        return _epoch * SLOTS_PER_EPOCH;
    }

    function computeEpochFirstSlotAt(uint256 _time) public pure returns (uint256) {
        return computeEpochFirstSlot(computeEpochAt(_time));
    }

    function computeSlotAt(uint256 _time) public pure returns (uint256) {
        return (_time - GENESIS_TIME) / SECONDS_PER_SLOT;
    }

    function computeEpochAt(uint256 _time) public pure returns (uint256) {
        return computeSlotAt(_time) / SLOTS_PER_EPOCH;
    }

    function setTimeToFrame0(MultiHashConsensusWithTimer consensus) public {
        consensus.setTimeInEpochs(INITIAL_EPOCH);
    }

    function getFastLaneLengthSlotsLimit(MultiHashConsensusWithTimer consensus)
        public
        view
        returns (uint256 fastLaneLengthSlotsLimit)
    {
        (, uint256 epochsPerFrame,) = consensus.getFrameConfig();
        (uint256 slotsPerEpoch,,) = consensus.getChainConfig();
        fastLaneLengthSlotsLimit = slotsPerEpoch * epochsPerFrame;
    }

    function hashArr1() public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](3);
        hashArr[0] = HASH_1;
        hashArr[1] = HASH_2;
        hashArr[2] = HASH_3;
        return hashArr;
    }

    function hashArr2() public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](3);
        hashArr[0] = HASH_1;
        hashArr[1] = HASH_3;
        hashArr[2] = HASH_2;
        return hashArr;
    }

    function hashArrZero() public pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function deployMultiHashConsensusMock() public returns (MultiHashConsensusWithTimer) {
        MultiHashConsensusWithTimer consensus = new MultiHashConsensusWithTimer();
        consensus.initialize(
            SLOTS_PER_EPOCH, SECONDS_PER_SLOT, GENESIS_TIME, EPOCHS_PER_FRAME, INITIAL_FAST_LANE_LENGTH_SLOTS, DAO
        );

        return consensus;
    }

    function deployWithdrawOracleMock(address consensus) public returns (WithdrawOracleWithTimer) {
        WithdrawOracleWithTimer oracle = new WithdrawOracleWithTimer();
        oracle.initialize(
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            consensus,
            CONSENSUS_VERSION,
            0,
            DAO,
            EXIT_REQUEST_LIMIT,
            CL_VAULT_MIN_SETTLE_LIMIT,
            CL_BALANCE,
            PENDING_BALANCE
        );
        return oracle;
    }

    function deployWithdrawOracle(address consensus) public returns (WithdrawOracle) {
        WithdrawOracle oracle = new WithdrawOracle();
        oracle.initialize(
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            consensus,
            CONSENSUS_VERSION,
            0,
            DAO,
            EXIT_REQUEST_LIMIT,
            CL_VAULT_MIN_SETTLE_LIMIT,
            CL_BALANCE,
            PENDING_BALANCE
        );
        return oracle;
    }

    function deployLargeStakeOracle(address consensus, address largeStake) public returns (LargeStakeOracle) {
        LargeStakeOracle oracle = new LargeStakeOracle();
        oracle.initialize(SECONDS_PER_SLOT, GENESIS_TIME, consensus, CONSENSUS_VERSION, 0, DAO, largeStake);
        return oracle;
    }

    function mockWithdrawOracleReportDataMock1Hash_1(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockWithdrawOracleReportDataMock1_1(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    function mockWithdrawOracleReportDataMock1_2(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportDataMock1 memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = 2;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](2);
        exitTokenIds[0] = 1;
        exitTokenIds[1] = 3;
        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](2);
        exitBlockNumbers[0] = 1000;
        exitBlockNumbers[1] = 1005;
        reportData.exitBlockNumbers = exitBlockNumbers;

        MockWithdrawInfo[] memory withdrawInfos = new MockWithdrawInfo[](2);

        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        MockWithdrawInfo memory withdrawInfo2 = MockWithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});

        withdrawInfos[0] = withdrawInfo1;
        withdrawInfos[1] = withdrawInfo2;

        reportData.withdrawInfos = withdrawInfos;
    }

    function mockWithdrawOracleReportDataMock1Hash_2(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockWithdrawOracleReportDataMock1_2(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    function mockWithdrawOracleReportDataMock1_3(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportDataMock1 memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = 3;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](3);
        exitTokenIds[0] = 1;
        exitTokenIds[1] = 3;
        exitTokenIds[2] = 5;
        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](3);
        exitBlockNumbers[0] = 1000;
        exitBlockNumbers[1] = 1005;
        exitBlockNumbers[2] = 1010;
        reportData.exitBlockNumbers = exitBlockNumbers;

        MockWithdrawInfo[] memory withdrawInfos = new MockWithdrawInfo[](2);

        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        MockWithdrawInfo memory withdrawInfo2 = MockWithdrawInfo({operatorId: 4, clRewards: 1e16, clCapital: 31 ether});

        withdrawInfos[0] = withdrawInfo1;
        withdrawInfos[1] = withdrawInfo2;

        reportData.withdrawInfos = withdrawInfos;
    }

    function mockWithdrawOracleReportDataMock1Hash_3(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockWithdrawOracleReportDataMock1_3(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    function mockDifferentStructHashIsSame() public pure returns (bool) {
        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        MockWithdrawInfo memory withdrawInfo2 = MockWithdrawInfo({operatorId: 4, clRewards: 1e16, clCapital: 31 ether});
        bytes32 hash1 = keccak256(abi.encode(withdrawInfo1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfo2));
        return hash1 == hash2;
    }

    function mockSameStructHashIsSame() public pure returns (bool) {
        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        MockWithdrawInfo memory withdrawInfo2 = MockWithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});

        bytes32 hash1 = keccak256(abi.encode(withdrawInfo1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfo2));
        return hash1 == hash2;
    }

    function mockDifferentStructArrayHashIsSame() public pure returns (bool) {
        MockWithdrawInfo[] memory withdrawInfos1 = new MockWithdrawInfo[](2);
        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        MockWithdrawInfo memory withdrawInfo2 = MockWithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});
        withdrawInfos1[0] = withdrawInfo1;
        withdrawInfos1[1] = withdrawInfo2;

        MockWithdrawInfo[] memory withdrawInfos2 = new MockWithdrawInfo[](2);
        MockWithdrawInfo memory withdrawInfo3 = MockWithdrawInfo({operatorId: 3, clRewards: 1e17, clCapital: 60 ether});
        MockWithdrawInfo memory withdrawInfo4 = MockWithdrawInfo({operatorId: 4, clRewards: 1e16, clCapital: 31 ether});
        withdrawInfos2[0] = withdrawInfo3;
        withdrawInfos2[1] = withdrawInfo4;

        bytes32 hash1 = keccak256(abi.encode(withdrawInfos1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfos2));
        return hash1 == hash2;
    }

    function mockSameStructArrayHashIsSame() public pure returns (bool) {
        MockWithdrawInfo[] memory withdrawInfos1 = new MockWithdrawInfo[](2);
        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        MockWithdrawInfo memory withdrawInfo2 = MockWithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});
        withdrawInfos1[0] = withdrawInfo1;
        withdrawInfos1[1] = withdrawInfo2;

        MockWithdrawInfo[] memory withdrawInfos2 = new MockWithdrawInfo[](2);
        MockWithdrawInfo memory withdrawInfo3 = MockWithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        MockWithdrawInfo memory withdrawInfo4 = MockWithdrawInfo({operatorId: 2, clRewards: 1e17, clCapital: 64 ether});
        withdrawInfos2[0] = withdrawInfo3;
        withdrawInfos2[1] = withdrawInfo4;

        bytes32 hash1 = keccak256(abi.encode(withdrawInfos1));
        bytes32 hash2 = keccak256(abi.encode(withdrawInfos2));
        return hash1 == hash2;
    }

    function mockWithdrawOracleReportDataMock1_count(uint256 refSlot, uint256 exitCount, uint256 opsCount)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportDataMock1 memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = exitCount;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](exitCount);
        for (uint256 i = 0; i < exitCount; ++i) {
            exitTokenIds[i] = i;
        }

        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](exitCount);
        for (uint256 i = 0; i < exitCount; ++i) {
            exitBlockNumbers[i] = 1001;
        }
        reportData.exitBlockNumbers = exitBlockNumbers;

        MockWithdrawInfo[] memory withdrawInfos = new MockWithdrawInfo[](opsCount);
        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 1, clRewards: 1e15, clCapital: 31 ether});
        for (uint256 i = 0; i < opsCount; ++i) {
            withdrawInfos[i] = withdrawInfo1;
        }

        reportData.withdrawInfos = withdrawInfos;
    }

    function mockWithdrawOracleReportDataMock1_countHash(uint256 refSlot, uint256 exitCount, uint256 opsCount)
        public
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockWithdrawOracleReportDataMock1_count(refSlot, exitCount, opsCount)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    function mockWithdrawOracleReportDataMock1_1(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportDataMock1 memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.reportExitedCount = 3;
        reportData.dataFormat = DATA_FORMAT_LIST;
        reportData.data = ZERO_BYTES;

        uint256[] memory exitTokenIds = new uint256[](3);
        exitTokenIds[0] = 1;
        exitTokenIds[1] = 3;
        exitTokenIds[2] = 5;
        reportData.exitTokenIds = exitTokenIds;

        uint256[] memory exitBlockNumbers = new uint256[](3);
        exitBlockNumbers[0] = 1000;
        exitBlockNumbers[1] = 1005;
        exitBlockNumbers[2] = 1010;
        reportData.exitBlockNumbers = exitBlockNumbers;

        MockWithdrawInfo[] memory withdrawInfos = new MockWithdrawInfo[](2);

        MockWithdrawInfo memory withdrawInfo1 = MockWithdrawInfo({operatorId: 1, clRewards: 1e17, clCapital: 64 ether});
        MockWithdrawInfo memory withdrawInfo2 = MockWithdrawInfo({operatorId: 2, clRewards: 1e16, clCapital: 31 ether});

        withdrawInfos[0] = withdrawInfo1;
        withdrawInfos[1] = withdrawInfo2;

        reportData.withdrawInfos = withdrawInfos;
    }

    ////////////////////////////////////////////////////////////////
    //------------ Real ReportData mock --------------------
    ////////////////////////////////////////////////////////////////

    //----------------------------- ReportData for not exit  -----------------------------------
    function mockFinalReportData_1(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        //        reportData.refSlot = 5414431;
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

    function mockFinalReportDataHash_1(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockFinalReportData_1(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    //----------------------------- ReportData for 3 validator exit  -----------------------------------
    function mockFinalReportData_3validatorExit(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 0;
        reportData.clVaultBalance = 3 * 32 ether;
        reportData.clSettleAmount = 0;
        reportData.reportExitedCount = 3;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](1);
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clReward: 0, clCapital: 0});
        withdrawInfos[0] = withdrawInfo1;
        reportData.withdrawInfos = withdrawInfos;

        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](3);
        ExitValidatorInfo memory exitValidatorInfo1 =
            ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 20100, slashAmount: 0});
        ExitValidatorInfo memory exitValidatorInfo2 =
            ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 20100, slashAmount: 0});
        ExitValidatorInfo memory exitValidatorInfo3 =
            ExitValidatorInfo({exitTokenId: 2, exitBlockNumber: 20100, slashAmount: 0});
        exitValidatorInfos[0] = exitValidatorInfo1;
        exitValidatorInfos[1] = exitValidatorInfo2;
        exitValidatorInfos[2] = exitValidatorInfo3;
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockFinalReportData_3validatorExit_hash(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockFinalReportData_3validatorExit(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    //----------------------------- ReportData for 3 validator exit and 1 delayed  -----------------------------------
    function mockFinalReportData_3validatorExit_1delayed(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 0;
        reportData.clVaultBalance = 3 * 32 ether;
        reportData.clSettleAmount = 0;
        reportData.reportExitedCount = 3;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](1);
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clReward: 0, clCapital: 0});
        withdrawInfos[0] = withdrawInfo1;
        reportData.withdrawInfos = withdrawInfos;

        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](3);
        ExitValidatorInfo memory exitValidatorInfo1 =
            ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 20100, slashAmount: 0});
        ExitValidatorInfo memory exitValidatorInfo2 =
            ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 20100, slashAmount: 0});
        ExitValidatorInfo memory exitValidatorInfo3 =
            ExitValidatorInfo({exitTokenId: 2, exitBlockNumber: 28000, slashAmount: 0});
        exitValidatorInfos[0] = exitValidatorInfo1;
        exitValidatorInfos[1] = exitValidatorInfo2;
        exitValidatorInfos[2] = exitValidatorInfo3;
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockFinalReportData_3validatorExit_1delayed_hash(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockFinalReportData_3validatorExit_1delayed(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    //----------------------------- ReportData for 3 NFT exit while 1 delayed; 1 largeExitRequest while 1 delayed  -----------------------------------
    function mockFinalReportData_3validatorExit_1delayed_1largeExitRequest_1delayed(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 0;
        reportData.clVaultBalance = 3 * 32 ether;
        reportData.clSettleAmount = 32 ether;
        reportData.reportExitedCount = 4;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](1);
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clReward: 0, clCapital: 32 ether});
        withdrawInfos[0] = withdrawInfo1;
        reportData.withdrawInfos = withdrawInfos;

        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](4);
        ExitValidatorInfo memory exitValidatorInfo1 =
            ExitValidatorInfo({exitTokenId: 0, exitBlockNumber: 20100, slashAmount: 0});
        ExitValidatorInfo memory exitValidatorInfo2 =
            ExitValidatorInfo({exitTokenId: 1, exitBlockNumber: 20100, slashAmount: 0});
        ExitValidatorInfo memory exitValidatorInfo3 =
            ExitValidatorInfo({exitTokenId: 2, exitBlockNumber: 28000, slashAmount: 0});

        ExitValidatorInfo memory exitValidatorInfo4 =
            ExitValidatorInfo({exitTokenId: 3, exitBlockNumber: 28100, slashAmount: 0});
        exitValidatorInfos[0] = exitValidatorInfo1;
        exitValidatorInfos[1] = exitValidatorInfo2;
        exitValidatorInfos[2] = exitValidatorInfo3;
        exitValidatorInfos[3] = exitValidatorInfo4;
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockFinalReportData_3validatorExit_1delayed_1largeExitRequest_1delayed_hash(uint256 refSlot)
        public
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash =
            keccak256(abi.encode(mockFinalReportData_3validatorExit_1delayed_1largeExitRequest_1delayed(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    //----------------------------- ReportData for OperatorReward  -----------------------------------
    function mockFinalReportData_OperatorReward(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 35 ether;
        reportData.clVaultBalance = 11 ether;
        reportData.clSettleAmount = 11 ether;
        reportData.reportExitedCount = 0;

        uint256 clReward1 = 11 ether * 3 / 4;
        uint256 clReward2 = 11 ether * 1 / 4;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](2);
        WithdrawInfo memory withdrawInfo1 = WithdrawInfo({operatorId: 1, clReward: uint96(clReward1), clCapital: 0});
        WithdrawInfo memory withdrawInfo2 = WithdrawInfo({operatorId: 1, clReward: uint96(clReward2), clCapital: 0});
        withdrawInfos[0] = withdrawInfo1;
        withdrawInfos[1] = withdrawInfo2;
        reportData.withdrawInfos = withdrawInfos;

        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](0);
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockFinalReportData_OperatorReward_hash(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockFinalReportData_OperatorReward(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    ////////////////////////////////////////////////////////////////
    //------------ Batch ReportData submit test and Gas test -------
    ////////////////////////////////////////////////////////////////

    function mockFinalReportData_batch100(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 100 ether;
        reportData.clVaultBalance = 20 ether;
        reportData.clSettleAmount = 20 ether;
        reportData.reportExitedCount = 100;

        uint256 clReward1 = 20 ether * 1 / 100;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](100);
        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](100);
        uint256[] memory delayedExitTokenIds = new uint256[](100);

        for (uint256 i = 0; i < 100; ++i) {
            WithdrawInfo memory withdrawInfo1 =
                WithdrawInfo({operatorId: uint64(i + 2), clReward: uint96(clReward1), clCapital: 0});
            withdrawInfos[i] = withdrawInfo1;

            ExitValidatorInfo memory exitValidatorInfo1 =
                ExitValidatorInfo({exitTokenId: uint64(i), exitBlockNumber: 28100, slashAmount: 0});
            exitValidatorInfos[i] = exitValidatorInfo1;

            delayedExitTokenIds[i] = i;
        }

        reportData.withdrawInfos = withdrawInfos;
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockFinalReportData_batch100_hash(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockFinalReportData_batch100(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    function mockFinalReportData_batch100_normal(uint256 refSlot)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 100 ether;
        reportData.clVaultBalance = 20 ether;
        reportData.clSettleAmount = 20 ether;
        reportData.reportExitedCount = 100;

        uint256 clReward1 = 20 ether * 1 / 50;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](50);
        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](100);

        for (uint256 i = 0; i < 50; ++i) {
            WithdrawInfo memory withdrawInfo1 =
                WithdrawInfo({operatorId: uint64(i + 2), clReward: uint96(clReward1), clCapital: 0});
            withdrawInfos[i] = withdrawInfo1;
        }

        for (uint256 i = 0; i < 100; ++i) {
            ExitValidatorInfo memory exitValidatorInfo1 =
                ExitValidatorInfo({exitTokenId: uint64(i), exitBlockNumber: 28100, slashAmount: 0});
            exitValidatorInfos[i] = exitValidatorInfo1;
        }

        reportData.withdrawInfos = withdrawInfos;
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockFinalReportData_batch100_normal_hash(uint256 refSlot) public pure returns (bytes32[] memory) {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockFinalReportData_batch100_normal(refSlot)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }

    function mockFinalReportDataNftOperatorForCount(uint256 refSlot, uint256 operatorCount, uint256 nftCount)
        public
        pure
        returns (WithdrawOracleWithTimer.ReportData memory reportData)
    {
        reportData.consensusVersion = CONSENSUS_VERSION;
        reportData.refSlot = refSlot;
        reportData.clBalance = 100 ether;
        reportData.clVaultBalance = operatorCount * 1e18;
        reportData.clSettleAmount = operatorCount * 1e18;
        reportData.reportExitedCount = nftCount;

        uint256 clReward1 = operatorCount * 1e18 * 1 / operatorCount;

        WithdrawInfo[] memory withdrawInfos = new WithdrawInfo[](operatorCount);
        ExitValidatorInfo[] memory exitValidatorInfos = new ExitValidatorInfo[](nftCount);

        for (uint256 i = 0; i < operatorCount; ++i) {
            WithdrawInfo memory withdrawInfo1 =
                WithdrawInfo({operatorId: uint64(i + 2), clReward: uint96(clReward1), clCapital: 0});
            withdrawInfos[i] = withdrawInfo1;
        }

        for (uint256 i = 0; i < nftCount; ++i) {
            ExitValidatorInfo memory exitValidatorInfo1 =
                ExitValidatorInfo({exitTokenId: uint64(i), exitBlockNumber: 28100, slashAmount: 0});
            exitValidatorInfos[i] = exitValidatorInfo1;
        }

        reportData.withdrawInfos = withdrawInfos;
        reportData.exitValidatorInfos = exitValidatorInfos;
    }

    function mockFinalReportDataNftOperatorForCount_hash(uint256 refSlot, uint256 operatorCount, uint256 nftCount)
        public
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory hashArr = new bytes32[](2);
        bytes32 hash = keccak256(abi.encode(mockFinalReportDataNftOperatorForCount(refSlot, operatorCount, nftCount)));
        hashArr[0] = hash;
        hashArr[1] = ZERO_HASH;
        return hashArr;
    }
}
