// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "src/interfaces/IELRewardFactory.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/IDepositContract.sol";
import "src/interfaces/IELReward.sol";
import "src/interfaces/IOperatorSlash.sol";
import {CLStakingInfo, CLStakingSlashInfo} from "src/library/ConsensusStruct.sol";

contract LargeStaking is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    IOperatorSlash public operatorSlashContract;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    address public consensusOracleContractAddr;
    IELRewardFactory public elRewardFactory;
    IDepositContract public depositContract;

    struct StakingInfo {
        uint256 stakingId; // Staking order id
        uint256 operatorId; // Specify which operator operates the validator
        uint256 stakingAmount; // The total amount of user stake
        uint256 alreadyStakingAmount; // Amount deposited into Eth2
        uint256 unstakeRequestAmount; // The amount the user requested to withdraw
        uint256 unstakeAmount; // Amount the user has withdrawn
        address owner; // The owner of the staking order，used for claim execution layer reward
        bytes withdrawCredentials; // Withdrawal certificate
        bool isELRewardSharing; // Whether to share the execution layer reward pool
    }

    StakingInfo[] public largeStakingList; // Staking order
    uint256 public totalLargeStakingCounts; // Total number of staking orders
    mapping(uint256 => uint256) internal totalLargeStakeAmounts; // key is operatorId
    uint256 public MIN_STAKE_AMOUNT;

    mapping(uint256 => bytes[]) public validators; // key is stakingId

    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;
    // dao el commisssionRate
    uint256 public daoElCommissionRate;

    mapping(uint256 => address) private privateELRewardCountract; // key is stakingId
    mapping(uint256 => address) private elRewardSharingCountract; // key is operatorId

    // share reward pool
    struct SettleInfo {
        uint256 valuePerSharePoint;
        uint256 rewardBalance;
    }

    mapping(uint256 => SettleInfo) private eLRewardSettleInfo; // key is stakingId
    mapping(uint256 => uint256) public unclaimedSharingRewards; // key is operatorId
    mapping(uint256 => uint256) public operatorSharingRewards; // key is operatorId
    mapping(uint256 => uint256) public daoSharingRewards; // key is operatorId
    mapping(uint256 => uint256) public totalShares; // key is operatorId
    mapping(uint256 => uint256) public valuePerShare; // key is operatorId
    uint256 private constant UNIT = 1e18;

    // private reward pool
    mapping(uint256 => uint256) public operatorPrivateRewards; // key is stakingId
    mapping(uint256 => uint256) public daoPrivateRewards; // key is stakingId
    mapping(uint256 => uint256) public unclaimedPrivateRewards; // key is stakingId

    error PermissionDenied();
    error InvalidParameter();
    error InvalidAddr();
    error InvalidAmount();
    error RequireOperatorTrusted();
    error InvalidWithdrawalCredentials();
    error InsufficientFunds();
    error InsufficientMargin();
    error InvalidRewardAddr();
    error InvalidRewardRatio();
    error InvalidReport();

    event LargeStake(
        uint256 _operatorId, uint256 _curStakingId, uint256 _amount, address _owner, bool _isELRewardSharing
    );
    event MigretaStake(
        uint256 _operatorId, uint256 _curStakingId, uint256 _amount, address _owner, bool _isELRewardSharing
    );
    event AppendStake(uint256 _stakingId, uint256 _amount);
    event ValidatorRegistered(uint256 _operatorId, uint256 _stakeingId, bytes _pubKey);
    event FastUnstake(uint256 _stakingId, uint256 _unstakeAmount);
    event LargeUnstake(uint256 _stakingId, uint256 _amount);
    event ELShareingRewardSettle(uint256 _operatorId, uint256 _daoReward, uint256 _operatorReward, uint256 _poolReward);
    event ElPrivateRewardSettle(
        uint256 _stakingId, uint256 _operatorId, uint256 _daoReward, uint256 _operatorReward, uint256 _poolReward
    );
    event UserRewardClaimed(uint256 _stakingId, address _beneficiary, uint256 _rewards);
    event OperatorRewardClaimed(uint256 _operatorId, address _rewardAddresses, uint256 _rewardAmounts);
    event OperatorPrivateRewardClaimed(uint256 _stakingId, uint256 _operatorId, uint256 _operatorRewards);
    event OperatorSharingRewardClaimed(uint256 _operatorId, uint256 _operatorRewards);
    event DaoPrivateRewardClaimed(uint256 _stakingId, address _daoVaultAddress, uint256 _daoRewards);
    event DaoSharingRewardClaimed(uint256 _operatorId, address daoVaultAddress, uint256 _daoRewards);
    event LargeStakingSlash(uint256[] _stakingIds, uint256[] _operatorIds, uint256[] _amounts);
    event ValidatorExitReport(uint256 _operatorId, uint256 _notReportedUnstakeAmount);
    event DaoAddressChanged(address _oldDao, address _dao);
    event DaoVaultAddressChanged(address _oldDaoVaultAddress, address _daoVaultAddress);
    event DaoELCommissionRateChanged(uint256 _oldDaoElCommissionRate, uint256 _daoElCommissionRate);
    event NodeOperatorsRegistryChanged(address _oldNodeOperatorRegistryContract, address _nodeOperatorRegistryAddress);
    event ConsensusOracleChanged(address _oldConsensusOracleContractAddr, address _consensusOracleContractAddr);
    event ELRewardFactoryChanged(address _oldElRewardFactory, address _elRewardFactory);
    event OperatorSlashChanged(address _oldOperatorSlashContract, address _operatorSlashContract);
    event MinStakeAmountChange(uint256 _oldMinStakeAmount, uint256 _minStakeAmount);

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    modifier onlyConsensusOracle() {
        if (msg.sender != consensusOracleContractAddr) revert PermissionDenied();
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address _dao,
        address _daoVaultAddress,
        address _nodeOperatorRegistryAddress,
        address _consensusOracleContractAddr,
        address _elRewardFactory,
        address _depositContract,
        address _operatorSlashContract
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        if (
            _nodeOperatorRegistryAddress == address(0) || _consensusOracleContractAddr == address(0)
                || _elRewardFactory == address(0) || _dao == address(0) || _daoVaultAddress == address(0)
                || _depositContract == address(0) || _operatorSlashContract == address(0)
        ) {
            revert InvalidAddr();
        }

        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryAddress);
        elRewardFactory = IELRewardFactory(_elRewardFactory);
        depositContract = IDepositContract(_depositContract);
        operatorSlashContract = IOperatorSlash(_operatorSlashContract);
        consensusOracleContractAddr = _consensusOracleContractAddr;
        dao = _dao;
        daoVaultAddress = _daoVaultAddress;
        daoElCommissionRate = 1000;
        MIN_STAKE_AMOUNT = 320 ether;
    }

    function largeStake(uint256 _operatorId, address _owner, address _withdrawCredentials, bool _isELRewardSharing)
        public
        payable
    {
        if (msg.value < MIN_STAKE_AMOUNT || msg.value % 32 ether != 0) revert InvalidAmount();
        // operatorId must be a trusted operator
        if (!nodeOperatorRegistryContract.isTrustedOperator(_operatorId)) revert RequireOperatorTrusted();

        if (_isELRewardSharing) {
            settleElSharingReward(_operatorId);
        }

        uint256 curStakingId;
        address elRewardAddr;
        (curStakingId, elRewardAddr) =
            _stake(_operatorId, _owner, _withdrawCredentials, _isELRewardSharing, msg.value, false);
        totalLargeStakeAmounts[_operatorId] += msg.value;
        emit LargeStake(_operatorId, curStakingId, msg.value, _owner, _isELRewardSharing);
    }

    function appendLargeStake(uint256 _stakingId, address _owner, address _withdrawCredentials) public payable {
        if (msg.value < 32 ether || msg.value % 32 ether != 0) revert InvalidAmount();
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        bytes memory userWithdrawalCredentials =
            bytes.concat(hex"010000000000000000000000", abi.encodePacked(_withdrawCredentials));

        if (
            stakingInfo.owner != _owner
                || keccak256(stakingInfo.withdrawCredentials) != keccak256(userWithdrawalCredentials)
        ) {
            revert InvalidParameter();
        }

        if (stakingInfo.isELRewardSharing) {
            settleElSharingReward(stakingInfo.operatorId);
            _updateShare(
                _stakingId,
                stakingInfo.operatorId,
                stakingInfo.stakingAmount - stakingInfo.unstakeAmount,
                msg.value,
                true
            );
        }

        largeStakingList[_stakingId].stakingAmount += msg.value;
        totalLargeStakeAmounts[stakingInfo.operatorId] += msg.value;

        emit AppendStake(_stakingId, msg.value);
    }

    function largeUnstake(uint256 _stakingId, uint256 _amount) public {
        StakingInfo storage stakingInfo = largeStakingList[_stakingId];
        if (
            _amount < 32 ether || _amount % 32 ether != 0
                || _amount > stakingInfo.stakingAmount - stakingInfo.unstakeRequestAmount
        ) revert InvalidAmount();

        if (msg.sender != stakingInfo.owner) revert PermissionDenied();

        uint256 _unstakeAmount = 0;
        if (stakingInfo.stakingAmount > stakingInfo.alreadyStakingAmount) {
            uint256 fastAmount = stakingInfo.stakingAmount - stakingInfo.alreadyStakingAmount;
            if (fastAmount > _amount) {
                _unstakeAmount = _amount;
            } else {
                _unstakeAmount = fastAmount;
            }
            stakingInfo.unstakeAmount += _unstakeAmount;
            payable(stakingInfo.owner).transfer(_unstakeAmount);
            emit FastUnstake(_stakingId, _unstakeAmount);
        }
        if (_unstakeAmount != _amount) {
            stakingInfo.unstakeRequestAmount += (_amount - _unstakeAmount);
        }

        emit LargeUnstake(_stakingId, _amount);
    }

    function migrateStake(
        address _owner,
        address _withdrawCredentials,
        bool _isELRewardSharing,
        bytes[] calldata _pubKeys
    ) public {
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        if (operatorId == 0) revert RequireOperatorTrusted();

        if (_isELRewardSharing) {
            settleElSharingReward(operatorId);
        }

        uint256 curStakingId;
        address elRewardAddr;
        uint256 stakeAmounts = _pubKeys.length * 32 ether;
        (curStakingId, elRewardAddr) =
            _stake(operatorId, _owner, _withdrawCredentials, _isELRewardSharing, stakeAmounts, true);
        for (uint256 i = 0; i < _pubKeys.length; ++i) {
            validators[curStakingId].push(_pubKeys[i]);
        }
        totalLargeStakeAmounts[operatorId] += stakeAmounts;

        emit MigretaStake(operatorId, curStakingId, stakeAmounts, _owner, _isELRewardSharing);
    }

    function appendMigrateStake(
        uint256 _stakingId,
        address _owner,
        address _withdrawCredentials,
        bytes[] calldata _pubKeys
    ) public {
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        bytes memory userWithdrawalCredentials =
            bytes.concat(hex"010000000000000000000000", abi.encodePacked(_withdrawCredentials));

        if (
            stakingInfo.owner != _owner
                || keccak256(stakingInfo.withdrawCredentials) != keccak256(userWithdrawalCredentials)
        ) {
            revert InvalidParameter();
        }

        uint256 stakeAmounts = _pubKeys.length * 32 ether;

        if (stakingInfo.isELRewardSharing) {
            settleElSharingReward(stakingInfo.operatorId);
            _updateShare(
                _stakingId,
                stakingInfo.operatorId,
                stakingInfo.stakingAmount - stakingInfo.unstakeAmount,
                stakeAmounts,
                true
            );
        }

        largeStakingList[_stakingId].stakingAmount += stakeAmounts;
        largeStakingList[_stakingId].alreadyStakingAmount += stakeAmounts;
        totalLargeStakeAmounts[stakingInfo.operatorId] += stakeAmounts;

        for (uint256 i = 0; i < _pubKeys.length; ++i) {
            validators[_stakingId].push(_pubKeys[i]);
        }

        emit MigretaStake(stakingInfo.operatorId, _stakingId, stakeAmounts, _owner, stakingInfo.isELRewardSharing);
    }

    function _stake(
        uint256 _operatorId,
        address _owner,
        address _withdrawCredentials,
        bool _isELRewardSharing,
        uint256 _stakingAmount,
        bool isMigrate
    ) internal returns (uint256, address) {
        if (_withdrawCredentials == address(0) || _withdrawCredentials.balance < 1 wei) {
            revert InvalidWithdrawalCredentials();
        }

        uint256 curStakingId = totalLargeStakingCounts;
        totalLargeStakingCounts++;

        bytes memory userWithdrawalCredentials =
            bytes.concat(hex"010000000000000000000000", abi.encodePacked(_withdrawCredentials));

        largeStakingList.push(
            StakingInfo({
                stakingId: curStakingId,
                operatorId: _operatorId,
                stakingAmount: _stakingAmount,
                alreadyStakingAmount: isMigrate ? _stakingAmount : 0,
                unstakeRequestAmount: 0,
                unstakeAmount: 0,
                owner: _owner,
                withdrawCredentials: userWithdrawalCredentials,
                isELRewardSharing: _isELRewardSharing
            })
        );

        address elRewardAddr;
        if (!_isELRewardSharing) {
            elRewardAddr = elRewardFactory.create(_operatorId, address(this));
            privateELRewardCountract[curStakingId] = elRewardAddr;
        } else {
            elRewardAddr = elRewardSharingCountract[_operatorId];
            if (address(0) == elRewardAddr) {
                elRewardAddr = elRewardFactory.create(_operatorId, address(this));
                elRewardSharingCountract[_operatorId] = elRewardAddr;
            }

            _updateShare(curStakingId, _operatorId, 0, _stakingAmount, true);
        }

        return (curStakingId, elRewardAddr);
    }

    function _updateShare(
        uint256 _stakingId,
        uint256 _operatorId,
        uint256 _curAmount,
        uint256 _updataAmount,
        bool _isStake
    ) internal {
        SettleInfo storage info = eLRewardSettleInfo[_stakingId];

        info.rewardBalance += (valuePerShare[_operatorId] - info.valuePerSharePoint) * (_curAmount) / UNIT;
        info.valuePerSharePoint = valuePerShare[_operatorId];

        if (_isStake) {
            totalShares[_operatorId] += _updataAmount;
        } else {
            totalShares[_operatorId] -= _updataAmount;
        }
    }

    function registerValidator(
        uint256 _stakingId,
        bytes[] calldata _pubkeys,
        bytes[] calldata _signatures,
        bytes32[] calldata _depositDataRoots
    ) external nonReentrant whenNotPaused {
        if (_pubkeys.length != _signatures.length || _pubkeys.length != _depositDataRoots.length) {
            revert InvalidParameter();
        }
        // must be a trusted operator
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        if (operatorId == 0) revert RequireOperatorTrusted();

        uint256 depositAmount = _pubkeys.length * 32 ether;
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        if ((stakingInfo.stakingAmount - stakingInfo.alreadyStakingAmount) < depositAmount) {
            revert InsufficientFunds();
        }
        bytes memory _withdrawalCredential = stakingInfo.withdrawCredentials;
        for (uint256 i = 0; i < _pubkeys.length; ++i) {
            depositContract.deposit{value: 32 ether}(
                _pubkeys[i], _withdrawalCredential, _signatures[i], _depositDataRoots[i]
            );
            emit ValidatorRegistered(operatorId, _stakingId, _pubkeys[i]);
            validators[_stakingId].push(_pubkeys[i]);
        }

        largeStakingList[_stakingId].alreadyStakingAmount += depositAmount;
    }

    function reward(uint256 _stakingId)
        public
        view
        returns (uint256 daoReward, uint256 operatorReward, uint256 userReward)
    {
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];

        if (stakingInfo.isELRewardSharing) {
            return _shareReward(_stakingId, stakingInfo.alreadyStakingAmount - stakingInfo.unstakeAmount);
        } else {
            return _privateReward(_stakingId);
        }
    }

    function _shareReward(uint256 _stakingId, uint256 amount)
        internal
        view
        returns (uint256 daoReward, uint256 operatorReward, uint256 userReward)
    {
        (uint256 operatorId,, uint256 rewards) = getRewardPoolInfo(_stakingId);

        SettleInfo memory settleInfo = eLRewardSettleInfo[_stakingId];
        daoReward = daoSharingRewards[operatorId];
        operatorReward = operatorSharingRewards[operatorId];
        userReward = settleInfo.rewardBalance;

        if (totalShares[operatorId] == 0 || rewards == 0) {
            return (daoReward, operatorReward, userReward);
        }

        uint256 unsettledDaoReward;
        uint256 unsettledOperatorReward;
        uint256 unsettledPoolReward;
        (unsettledDaoReward, unsettledOperatorReward, unsettledPoolReward) = _calcElReward(rewards, operatorId);
        daoReward += unsettledDaoReward;
        operatorReward += unsettledOperatorReward;

        uint256 unsettledUserReward = (
            valuePerShare[operatorId] + unsettledPoolReward * UNIT / totalShares[operatorId]
                - settleInfo.valuePerSharePoint
        ) * amount / UNIT;
        userReward += unsettledUserReward;
    }

    function _privateReward(uint256 _stakingId)
        internal
        view
        returns (uint256 daoReward, uint256 operatorReward, uint256 userReward)
    {
        daoReward = daoPrivateRewards[_stakingId];
        operatorReward = operatorPrivateRewards[_stakingId];

        (uint256 operatorId,, uint256 rewards) = getRewardPoolInfo(_stakingId);
        if (rewards == 0) {
            return (daoReward, operatorReward, 0);
        }

        uint256 unsettledDaoReward;
        uint256 unsettledOperatorReward;
        uint256 unsettledPoolReward;
        (unsettledDaoReward, unsettledOperatorReward, unsettledPoolReward) = _calcElReward(rewards, operatorId);
        daoReward += unsettledDaoReward;
        operatorReward += unsettledOperatorReward;
        userReward = unsettledPoolReward;
        return (daoReward, operatorReward, userReward);
    }

    function getRewardPoolInfo(uint256 _stakingId)
        public
        view
        returns (uint256 operatorId, address rewardPoolAddr, uint256 rewards)
    {
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        operatorId = stakingInfo.operatorId;
        if (stakingInfo.isELRewardSharing) {
            rewardPoolAddr = elRewardSharingCountract[operatorId];
            rewards = rewardPoolAddr.balance - unclaimedSharingRewards[operatorId];
        } else {
            rewardPoolAddr = privateELRewardCountract[_stakingId];
            rewards = rewardPoolAddr.balance - unclaimedPrivateRewards[_stakingId];
        }
        return (operatorId, rewardPoolAddr, rewards);
    }

    function settleElSharingReward(uint256 _operatorId) public {
        address rewardPoolAddr = elRewardSharingCountract[_operatorId];
        uint256 rewards = rewardPoolAddr.balance - unclaimedSharingRewards[_operatorId];

        (uint256 daoReward, uint256 operatorReward, uint256 poolReward) = _calcElReward(rewards, _operatorId);
        if (poolReward == 0 || totalShares[_operatorId] == 0) return;

        operatorSharingRewards[_operatorId] += operatorReward;
        daoSharingRewards[_operatorId] += daoReward;
        unclaimedSharingRewards[_operatorId] = rewardPoolAddr.balance;

        valuePerShare[_operatorId] += poolReward * UNIT / totalShares[_operatorId]; // settle

        emit ELShareingRewardSettle(_operatorId, daoReward, operatorReward, poolReward);
    }

    function settleElPrivateReward(uint256 _stakingId) public {
        address rewardPoolAddr = privateELRewardCountract[_stakingId];
        uint256 _operatorId = largeStakingList[_stakingId].operatorId;
        uint256 rewards = rewardPoolAddr.balance - unclaimedPrivateRewards[_stakingId];
        (uint256 daoReward, uint256 operatorReward, uint256 poolReward) = _calcElReward(rewards, _operatorId);
        if (poolReward == 0) return;
        unclaimedPrivateRewards[_stakingId] = rewardPoolAddr.balance;
        operatorPrivateRewards[_stakingId] += operatorReward;
        daoPrivateRewards[_stakingId] += daoReward;

        emit ElPrivateRewardSettle(_stakingId, _operatorId, daoReward, operatorReward, poolReward);
    }

    function _calcElReward(uint256 rewards, uint256 _operatorId)
        internal
        view
        returns (uint256 daoReward, uint256 operatorReward, uint256 poolReward)
    {
        if (rewards == 0) return (0, 0, 0);

        uint256[] memory _operatorIds = new uint256[] (1);
        _operatorIds[0] = _operatorId;
        uint256[] memory operatorElCommissionRate;
        operatorElCommissionRate = nodeOperatorRegistryContract.getOperatorCommissionRate(_operatorIds);
        operatorReward = (rewards * operatorElCommissionRate[0]) / 10000;
        daoReward = (rewards * daoElCommissionRate) / 10000;
        poolReward = rewards - operatorReward - daoReward;
        return (daoReward, operatorReward, poolReward);
    }

    function claimRewardsOfUser(uint256 _stakingId, address beneficiary, uint256 rewards) public {
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        if (beneficiary == address(0) || msg.sender != stakingInfo.owner) revert PermissionDenied();

        SettleInfo storage settleInfo = eLRewardSettleInfo[_stakingId];

        address rewardPoolAddr;
        if (stakingInfo.isELRewardSharing) {
            settleElSharingReward(stakingInfo.operatorId);

            rewardPoolAddr = elRewardSharingCountract[stakingInfo.operatorId];

            uint256 totalRewards = settleInfo.rewardBalance
                + (valuePerShare[stakingInfo.operatorId] - settleInfo.valuePerSharePoint)
                    * (stakingInfo.stakingAmount - stakingInfo.unstakeAmount) / UNIT;

            settleInfo.valuePerSharePoint = valuePerShare[stakingInfo.operatorId];

            settleInfo.rewardBalance = totalRewards - rewards;
            unclaimedSharingRewards[stakingInfo.operatorId] -= rewards;
        } else {
            settleElPrivateReward(_stakingId);
            rewardPoolAddr = privateELRewardCountract[_stakingId];
            if (
                rewards + operatorPrivateRewards[_stakingId] + daoPrivateRewards[_stakingId]
                    > unclaimedPrivateRewards[_stakingId]
            ) {
                revert InvalidAmount();
            }
            unclaimedPrivateRewards[_stakingId] -= rewards;
        }

        IELReward(rewardPoolAddr).transfer(rewards, beneficiary);
        emit UserRewardClaimed(_stakingId, beneficiary, rewards);

        uint256[] memory _stakingIds = new uint256[] (1);
        _stakingIds[0] = _stakingId;
        operatorSlashContract.claimCompensatedOfLargeStaking(_stakingIds, beneficiary);
    }

    function claimRewardsOfOperator(uint256[] memory _privatePoolStakingIds, bool _claimSharePool, uint256 _operatorId)
        external
    {
        StakingInfo memory stakingInfo;
        uint256 pledgeBalance = 0;
        uint256 requirBalance = 0;

        for (uint256 i = 0; i < _privatePoolStakingIds.length; ++i) {
            uint256 stakingId = _privatePoolStakingIds[i];
            stakingInfo = largeStakingList[stakingId];
            if (stakingInfo.isELRewardSharing) {
                continue;
            }

            (pledgeBalance, requirBalance) =
                nodeOperatorRegistryContract.getPledgeInfoOfOperator(stakingInfo.operatorId);
            if (pledgeBalance < requirBalance) revert InsufficientMargin();

            settleElPrivateReward(stakingId);
            uint256 operatorRewards = operatorPrivateRewards[stakingId];
            operatorPrivateRewards[stakingId] = 0;
            unclaimedPrivateRewards[stakingId] -= operatorRewards;
            emit OperatorPrivateRewardClaimed(stakingId, stakingInfo.operatorId, operatorRewards);
            _distributeOperatorRewards(privateELRewardCountract[stakingId], operatorRewards, stakingInfo.operatorId);
        }

        if (_claimSharePool) {
            (pledgeBalance, requirBalance) = nodeOperatorRegistryContract.getPledgeInfoOfOperator(_operatorId);
            if (pledgeBalance < requirBalance) revert InsufficientMargin();
            settleElSharingReward(_operatorId);
            uint256 operatorRewards = operatorSharingRewards[_operatorId];
            operatorSharingRewards[_operatorId] = 0;
            unclaimedSharingRewards[_operatorId] -= operatorRewards;
            emit OperatorSharingRewardClaimed(stakingInfo.operatorId, operatorRewards);
            _distributeOperatorRewards(elRewardSharingCountract[_operatorId], operatorRewards, _operatorId);
        }
    }

    function _distributeOperatorRewards(address _elRewardContract, uint256 _operatorRewards, uint256 _operatorId)
        internal
    {
        address[] memory rewardAddresses;
        uint256[] memory ratios;
        uint256 totalAmount = 0;
        uint256 totalRatios = 0;

        (rewardAddresses, ratios) = nodeOperatorRegistryContract.getNodeOperatorRewardSetting(_operatorId);
        if (rewardAddresses.length == 0) revert InvalidRewardAddr();
        uint256[] memory rewardAmounts = new uint256[] (rewardAddresses.length);

        totalAmount = 0;
        totalRatios = 0;
        for (uint256 i = 0; i < rewardAddresses.length; ++i) {
            uint256 ratio = ratios[i];
            totalRatios += ratio;

            // If it is the last reward address, calculate by subtraction
            if (i == rewardAddresses.length - 1) {
                rewardAmounts[i] = _operatorRewards - totalAmount;
            } else {
                uint256 amount = _operatorRewards * ratio / 100;
                rewardAmounts[i] = amount;
                totalAmount += amount;
            }
        }

        if (totalRatios != 100) revert InvalidRewardRatio();

        for (uint256 j = 0; j < rewardAddresses.length; ++j) {
            IELReward(_elRewardContract).transfer(rewardAmounts[j], rewardAddresses[j]);
            emit OperatorRewardClaimed(_operatorId, rewardAddresses[j], rewardAmounts[j]);
        }
    }

    function claimRewardsOfDao(uint256[] memory _privatePoolStakingIds, uint256[] memory _operatorIds) external {
        StakingInfo memory stakingInfo;
        for (uint256 i = 0; i < _privatePoolStakingIds.length; ++i) {
            uint256 stakingId = _privatePoolStakingIds[i];
            stakingInfo = largeStakingList[stakingId];
            if (stakingInfo.isELRewardSharing) {
                continue;
            }

            settleElPrivateReward(stakingId);
            uint256 daoRewards = daoPrivateRewards[stakingId];
            daoPrivateRewards[stakingId] = 0;
            unclaimedPrivateRewards[stakingId] -= daoRewards;

            IELReward(privateELRewardCountract[stakingId]).transfer(daoRewards, daoVaultAddress);
            emit DaoPrivateRewardClaimed(stakingId, daoVaultAddress, daoRewards);
        }

        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 operatorId = _operatorIds[i];
            settleElSharingReward(operatorId);
            uint256 daoRewards = daoSharingRewards[operatorId];
            daoSharingRewards[operatorId] = 0;
            unclaimedSharingRewards[operatorId] -= daoRewards;

            IELReward(elRewardSharingCountract[operatorId]).transfer(daoRewards, daoVaultAddress);
            emit DaoSharingRewardClaimed(operatorId, daoVaultAddress, daoRewards);
        }
    }

    function reportCLStakingData(CLStakingInfo[] memory _clStakingInfo, CLStakingSlashInfo[] memory _clStakingSlashInfo)
        external
        onlyConsensusOracle
    {
        StakingInfo memory stakingInfo;
        for (uint256 i = 0; i < _clStakingInfo.length; ++i) {
            CLStakingInfo memory sInfo = _clStakingInfo[i];
            if (sInfo.notReportedUnstakeAmount % 32 ether != 0 || sInfo.stakingId > largeStakingList.length) {
                revert InvalidReport();
            }
            stakingInfo = largeStakingList[sInfo.stakingId];
            if (stakingInfo.isELRewardSharing) {
                settleElSharingReward(stakingInfo.operatorId);
                _updateShare(
                    sInfo.stakingId,
                    stakingInfo.operatorId,
                    stakingInfo.stakingAmount - stakingInfo.unstakeAmount,
                    sInfo.notReportedUnstakeAmount,
                    false
                );
            }

            largeStakingList[sInfo.stakingId].unstakeAmount += sInfo.notReportedUnstakeAmount;
            totalLargeStakeAmounts[stakingInfo.operatorId] -= sInfo.notReportedUnstakeAmount;
            emit ValidatorExitReport(stakingInfo.operatorId, sInfo.notReportedUnstakeAmount);
        }

        uint256[] memory _stakingIds = new uint256[] (_clStakingSlashInfo.length);
        uint256[] memory _operatorIds = new uint256[] (_clStakingSlashInfo.length);
        uint256[] memory _amounts = new uint256[] (_clStakingSlashInfo.length);
        for (uint256 i = 0; i < _clStakingSlashInfo.length; ++i) {
            CLStakingSlashInfo memory sInfo = _clStakingSlashInfo[i];
            _stakingIds[i] = sInfo.stakingId;
            _operatorIds[i] = largeStakingList[sInfo.stakingId].operatorId;
            _amounts[i] = sInfo.slashAmount;
        }

        if (_clStakingSlashInfo.length != 0) {
            operatorSlashContract.slashOperatorOfLargeStaking(_stakingIds, _operatorIds, _amounts);
            emit LargeStakingSlash(_stakingIds, _operatorIds, _amounts);
        }
    }

    function getOperatorValidatorCounts(uint256 _operatorId) external view returns (uint256) {
        return totalLargeStakeAmounts[_operatorId] / 32 ether;
    }

    function getStakingInfoOfOwner(address _owner) public view returns (StakingInfo[] memory) {
        uint256 number = 0;
        for (uint256 i = 0; i < largeStakingList.length; ++i) {
            if (largeStakingList[i].owner == _owner) {
                number += 1;
            }
        }
        StakingInfo[] memory userStakings = new StakingInfo[] (number);
        uint256 index = 0;
        for (uint256 i = 0; i < largeStakingList.length; ++i) {
            if (largeStakingList[i].owner == _owner) {
                userStakings[index++] = largeStakingList[i];
            }
        }

        return userStakings;
    }

    function setLargeStakingSetting(
        address _dao,
        address _daoVaultAddress,
        uint256 _daoElCommissionRate,
        uint256 _MIN_STAKE_AMOUNT,
        address _nodeOperatorRegistryAddress,
        address _consensusOracleContractAddr,
        address _elRewardFactory,
        address _operatorSlashContract
    ) public onlyDao {
        if (_dao != address(0)) {
            emit DaoAddressChanged(dao, _dao);
            dao = _dao;
        }

        if (_daoVaultAddress != address(0)) {
            emit DaoVaultAddressChanged(daoVaultAddress, _daoVaultAddress);
            daoVaultAddress = _daoVaultAddress;
        }

        if (_daoElCommissionRate != 0) {
            emit DaoELCommissionRateChanged(daoElCommissionRate, _daoElCommissionRate);
            daoElCommissionRate = _daoElCommissionRate;
        }

        if (_MIN_STAKE_AMOUNT != 0) {
            emit MinStakeAmountChange(MIN_STAKE_AMOUNT, _MIN_STAKE_AMOUNT);
            MIN_STAKE_AMOUNT = _MIN_STAKE_AMOUNT;
        }

        if (_nodeOperatorRegistryAddress != address(0)) {
            emit NodeOperatorsRegistryChanged(address(nodeOperatorRegistryContract), _nodeOperatorRegistryAddress);
            nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryAddress);
        }

        if (_consensusOracleContractAddr != address(0)) {
            emit ConsensusOracleChanged(consensusOracleContractAddr, _consensusOracleContractAddr);
            consensusOracleContractAddr = _consensusOracleContractAddr;
        }

        if (_elRewardFactory != address(0)) {
            emit ELRewardFactoryChanged(address(elRewardFactory), _elRewardFactory);
            elRewardFactory = IELRewardFactory(_elRewardFactory);
        }

        if (_operatorSlashContract != address(0)) {
            emit OperatorSlashChanged(address(operatorSlashContract), _operatorSlashContract);
            operatorSlashContract = IOperatorSlash(_operatorSlashContract);
        }
    }
}
