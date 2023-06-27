// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "test/helpers/oracles/MultiHashConsensusWithTimer.sol";
import "test/helpers/oracles/MockLargeOracleProvider.sol";
import "src/oracles/WithdrawOracle.sol";
import "src/oracles/LargeStakeOracle.sol";
import "src/largeStaking/LargeStaking.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/mocks/DepositContract.sol";
import "src/OperatorSlash.sol";
import "src/largeStaking/ELRewardFactory.sol";
import "src/LiquidStaking.sol";
import "src/vault/VaultManager.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/vault/ELVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/ConsensusVault.sol";
import "src/WithdrawalRequest.sol";
import "src/largeStaking/ELReward.sol";
import "src/utils/Array.sol";

// forge test --match-path  test/oracles/LargeStakeOracleTest.sol
contract WithdrawOracleTest is Test, MockLargeOracleProvider {
    MultiHashConsensusWithTimer consensus;
    WithdrawOracle withdrawOracle;
    LargeStakeOracle largeStakeOracle;

    uint256 WithdrawOracleModuleId = 1;
    uint256 largeStakeOracleModuleId = 2;

    ////////////////////////////////////////////////////////////////
    //------------ init and set other contracts --------------------
    ////////////////////////////////////////////////////////////////
    LiquidStaking liquidStaking;
    NETH neth;
    VNFT vnft;
    VaultManager vaultManager;
    NodeOperatorRegistry operatorRegistry;
    DepositContract depositContract;
    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    ConsensusVault consensusVaultContract;
    address payable consensusVaultContractAddr;
    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;
    LargeStaking largeStaking;
    ELReward elReward;
    ELRewardFactory elRewardFactor;

    address _dao = DAO;
    address _daoValutAddress = address(2);
    address _rewardAddress = address(3);
    address _controllerAddress = address(1000);
    address _controllerAddress2 = address(1001);
    address[] _rewardAddresses = new address[] (1);
    uint256[] _ratios = new uint256[] (1);
    uint256 moduleId = 1;

    function initAndSetOtherContract() public {
        _rewardAddresses[0] = address(5);
        _ratios[0] = 100;
        liquidStaking = new LiquidStaking();

        consensusVaultContract = new ConsensusVault();
        consensusVaultContract.initialize(_dao, address(liquidStaking));
        consensusVaultContractAddr = payable(consensusVaultContract);

        neth = new NETH();
        neth.setLiquidStaking(address(liquidStaking));

        vnft = new VNFT();
        vnft.initialize();
        vnft.setLiquidStaking(address(liquidStaking));

        vaultContract = new ELVault();
        vaultFactoryContract = new ELVaultFactory();
        vaultFactoryContract.initialize(address(vaultContract), address(liquidStaking), _dao);

        operatorRegistry = new NodeOperatorRegistry();
        operatorRegistry.initialize(_dao, _daoValutAddress, address(vaultFactoryContract), address(vnft));
        vm.prank(_dao);
        operatorRegistry.setNodeOperatorregistrySetting(
            address(0), address(0), address(liquidStaking), address(0), address(0), 0, 0, 0
        );
        vaultFactoryContract.setNodeOperatorRegistry(address(operatorRegistry));

        depositContract = new DepositContract();

        liquidStaking.initialize(
            _dao,
            _daoValutAddress,
            hex"01000000000000000000000000dfaae92ed72a05bc61262aa164f38b5626e106",
            address(operatorRegistry),
            address(neth),
            address(vnft),
            address(withdrawOracle),
            address(depositContract)
        );

        vm.prank(_dao);
        liquidStaking.setOperatorCanLoanAmounts(32 ether);

        operatorRegistry.registerOperator{value: 1.1 ether}(
            "one", _controllerAddress, address(4), _rewardAddresses, _ratios
        );

        vm.prank(_dao);
        operatorRegistry.setTrustedOperator(1);

        vaultManager = new VaultManager();

        uint256[] memory _operatorIds = new uint256[](0);
        address[] memory _users = new address[](0);
        uint256[] memory _nethAmounts = new uint256[](0);

        withdrawalRequest = new WithdrawalRequest();
        withdrawalRequest.initialize(
            _dao, address(liquidStaking), address(vnft), address(neth), address(operatorRegistry), address(vaultManager)
        );

        operatorSlash = new OperatorSlash();
        operatorSlash.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawalRequest),
            address(vaultManager),
            7200
        );

        vm.prank(_dao);
        operatorRegistry.setNodeOperatorregistrySetting(
            address(0), address(0), address(0), address(operatorSlash), address(0), 0, 0, 0
        );
        vm.prank(_dao);
        liquidStaking.initializeV2(
            _operatorIds,
            _users,
            _nethAmounts,
            address(consensusVaultContract),
            address(vaultManager),
            address(withdrawalRequest),
            address(operatorSlash),
            address(withdrawOracle)
        );

        vaultManager.initialize(
            _dao,
            address(liquidStaking),
            address(vnft),
            address(operatorRegistry),
            address(withdrawOracle),
            address(operatorSlash)
        );

        elReward = new ELReward();
        elRewardFactor = new ELRewardFactory();
        elRewardFactor.initialize(address(elReward), _dao);
        largeStaking = new LargeStaking();
        largeStaking.initialize(
            _dao,
            _daoValutAddress,
            address(operatorRegistry),
            address(withdrawOracle),
            address(elRewardFactor),
            address(depositContract),
            address(operatorSlash)
        );
        vm.prank(_dao);
        operatorRegistry.initializeV3(address(largeStaking));
    }

    ////////////////////////////////////////////////////////////////

    function setUp() public {
        consensus = deployMultiHashConsensusMock();
        withdrawOracle = deployWithdrawOracle(address(consensus));
        largeStakeOracle = deployLargeStakeOracle(address(consensus), address(largeStaking));

        initAndSetOtherContract();

        vm.startPrank(DAO);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
        consensus.setTime(GENESIS_TIME + INITIAL_EPOCH * SLOTS_PER_EPOCH * SECONDS_PER_SLOT);

        consensus.addReportProcessor(address(withdrawOracle));
        consensus.addReportProcessor(address(largeStakeOracle));

        consensus.addMember(MEMBER_1, 1);
        consensus.addMember(MEMBER_2, 3);
        consensus.addMember(MEMBER_3, 3);
        consensus.addMember(MEMBER_4, 3);

        withdrawOracle.setLiquidStaking(address(liquidStaking));
        withdrawOracle.setVaultManager(address(vaultManager));
        withdrawOracle.updateContractVersion(WITHDRAW_ORACLE_CONTRACT_VERSION);

        vm.stopPrank();
    }

    /////////////////////////  test 1 consensus 2 oracle report  ///////////////////////////////////////

    function reportDataConsensusReached(bytes32[] memory hash) public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        vm.prank(MEMBER_1);
        consensus.submitReport(refSlot, hash);
        (, bytes32[] memory consensusReport) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport, hashArrZero()));

        bool isReportProcessing = consensus.getIsReportProcessing(address(withdrawOracle));
        assertFalse(isReportProcessing);

        vm.prank(MEMBER_2);
        consensus.submitReport(refSlot, hash);
        vm.prank(MEMBER_3);
        consensus.submitReport(refSlot, hash);

        // committee reaches consensus
        console.log("committee reaches consensus");

        (uint256 refSlot2, bytes32[] memory consensusReport2) = consensus.getConsensusState();
        assertTrue(Array.compareBytes32Arrays(consensusReport2, hash));
        assertEq(refSlot2, refSlot);

        bool isReportProcessing2 = consensus.getIsReportProcessing(address(withdrawOracle));
        assertFalse(isReportProcessing2);

        (bytes32 reportHash, uint256 reportRefSlot, uint256 reportProcessingDeadlineTime, bool reportProcessingStarted)
        = withdrawOracle.getConsensusReport();
        assertEq(reportHash, hash[0]);
        assertEq(reportRefSlot, refSlot);
        assertEq(reportProcessingDeadlineTime, computeTimestampAtSlot(refSlot + SLOTS_PER_FRAME));
        assertFalse(reportProcessingStarted);

        (uint256 curRefSlot, uint256 reportProcessingDeadlineSlot) = consensus.getCurrentFrame();
        WithdrawOracle.ProcessingState memory procState = withdrawOracle.getProcessingState();

        assertEq(procState.currentFrameRefSlot, curRefSlot);
        assertEq(procState.dataHash, reportHash);
        assertEq(procState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertFalse(procState.dataSubmitted);
        assertEq(procState.reportExitedCount, 0);

        (
            bytes32 largeStakeOracleReportHash,
            uint256 largeStakeOracleReportRefSlot,
            uint256 largeStakeOracleReportProcessingDeadlineTime,
            bool largeStakeOracleReportProcessingStarted
        ) = largeStakeOracle.getConsensusReport();

        LargeStakeOracle.ProcessingState memory largeStakeOracleProcState = largeStakeOracle.getProcessingState();
        assertEq(largeStakeOracleProcState.currentFrameRefSlot, curRefSlot);
        assertEq(largeStakeOracleProcState.dataHash, largeStakeOracleReportHash);
        assertEq(largeStakeOracleProcState.processingDeadlineTime, computeTimestampAtSlot(reportProcessingDeadlineSlot));
        assertFalse(largeStakeOracleProcState.dataSubmitted);
    }

    // forge test -vvvv --match-test testTwoOracleConsensusReached
    function testTwoOracleConsensusReached() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hashArr = mockLargeStakeOracleEmptyReportDataHash(refSlot);
        reportDataConsensusReached(hashArr);
    }

    // forge test -vvvv --match-test testWithdrawOracleReport
    function testWithdrawOracleReport() public {
        (uint256 refSlot,) = consensus.getCurrentFrame();

        bytes32[] memory hashArr = mockLargeStakeOracleEmptyReportDataHash(refSlot);
        reportDataConsensusReached(hashArr);

        vm.prank(MEMBER_1);
        withdrawOracle.submitReportData(mockWithdrawOracleNoExitReportData(refSlot), WITHDRAW_ORACLE_CONTRACT_VERSION, WithdrawOracleModuleId);
    }
}
