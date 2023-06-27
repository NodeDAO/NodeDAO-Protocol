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
import "src/interfaces/ILargeStaking.sol";
import {CLStakingInfo, CLStakingSlashInfo} from "src/library/ConsensusStruct.sol";

contract LargeStaking is
    ILargeStaking,
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
        bool isELRewardSharing; // Whether to share the execution layer reward pool
        uint256 stakingId; // Staking order id
        uint256 operatorId; // Specify which operator operates the validator
        uint256 stakingAmount; // The total amount of user stake
        uint256 alreadyUsedAmount; // Amount deposited into Eth2 or unstake
        uint256 unstakeRequestAmount; // The amount the user requested to withdraw
        uint256 unstakeAmount; // Amount the user has withdrawn
        address owner; // The owner of the staking order，used for claim execution layer reward
        bytes32 withdrawCredentials; // Withdrawal certificate
    }

    StakingInfo[] public largeStakingList; // Staking order
    mapping(uint256 => uint256) internal totalLargeStakeAmounts; // key is operatorId

    uint256 public MIN_STAKE_AMOUNT;

    mapping(uint256 => bytes[]) public validators; // key is stakingId
    mapping(bytes => uint256) public validatorOfOperator; // key is pubkey, value is operatorId

    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;
    // dao el commisssionRate
    uint256 public daoElCommissionRate;

    mapping(uint256 => address) public elPrivateRewardPool; // key is stakingId
    mapping(uint256 => address) public elSharedRewardPool; // key is operatorId

    // share reward pool
    struct SettleInfo {
        uint256 valuePerSharePoint;
        uint256 rewardBalance;
    }

    mapping(uint256 => SettleInfo) public eLSharedRewardSettleInfo; // key is stakingId
    mapping(uint256 => uint256) public unclaimedSharedRewards; // key is operatorId
    mapping(uint256 => uint256) public operatorSharedRewards; // key is operatorId
    mapping(uint256 => uint256) public daoSharedRewards; // key is operatorId
    mapping(uint256 => uint256) public totalShares; // key is operatorId
    mapping(uint256 => uint256) public valuePerShare; // key is operatorId
    uint256 private constant UNIT = 1e18;

    // private reward pool
    mapping(uint256 => uint256) public operatorPrivateRewards; // key is stakingId
    mapping(uint256 => uint256) public daoPrivateRewards; // key is stakingId
    mapping(uint256 => uint256) public unclaimedPrivateRewards; // key is stakingId

    // report data
    mapping(bytes => uint256) public validatorExitReportBlock;
    mapping(bytes => uint256) public validatorSlashAmount;

    error PermissionDenied();
    error InvalidParameter();
    error InvalidAddr();
    error InvalidAmount();
    error SharedRewardPoolOpened();
    error SharedRewardPoolNotOpened();
    error RequireOperatorTrusted();
    error InvalidWithdrawalCredentials();
    error InsufficientFunds();
    error InsufficientMargin();
    error InvalidRewardAddr();
    error InvalidRewardRatio();
    error InvalidReport();

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
        address _operatorSlashContract,
        address _consensusOracleContractAddr,
        address _elRewardFactory,
        address _depositContract
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

    function startupSharedRewardPool(uint256 _operatorId) public {
        (,, address owner,,) = nodeOperatorRegistryContract.getNodeOperator(_operatorId, false);
        if (msg.sender != owner) revert PermissionDenied();

        address elRewardPoolAddr = elSharedRewardPool[_operatorId];
        if (elRewardPoolAddr != address(0)) revert SharedRewardPoolOpened();

        elRewardPoolAddr = elRewardFactory.create(_operatorId, address(this));
        elSharedRewardPool[_operatorId] = elRewardPoolAddr;

        emit SharedRewardPoolStart(_operatorId, elRewardPoolAddr);
    }

    function largeStake(uint256 _operatorId, address _owner, address _withdrawCredentials, bool _isELRewardSharing)
        public
        payable
    {
        if (msg.value < MIN_STAKE_AMOUNT || msg.value % 32 ether != 0) revert InvalidAmount();
        // operatorId must be a trusted operator
        if (!nodeOperatorRegistryContract.isTrustedOperator(_operatorId)) revert RequireOperatorTrusted();

        if (_isELRewardSharing) {
            settleElSharedReward(_operatorId);
        }

        uint256 curStakingId;
        address elRewardPoolAddr;
        (curStakingId, elRewardPoolAddr) =
            _stake(_operatorId, _owner, _withdrawCredentials, _isELRewardSharing, msg.value, false);
        totalLargeStakeAmounts[_operatorId] += msg.value;
        emit LargeStake(_operatorId, curStakingId, msg.value, _owner, _withdrawCredentials, _isELRewardSharing);
    }

    function appendLargeStake(uint256 _stakingId, address _owner, address _withdrawCredentials) public payable {
        if (msg.value < 32 ether || msg.value % 32 ether != 0) revert InvalidAmount();
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        bytes32 userWithdrawalCredentials = getWithdrawCredentials(_withdrawCredentials);

        if (stakingInfo.owner != _owner || stakingInfo.withdrawCredentials != userWithdrawalCredentials) {
            revert InvalidParameter();
        }

        if (stakingInfo.isELRewardSharing) {
            settleElSharedReward(stakingInfo.operatorId);
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
        if (stakingInfo.stakingAmount > stakingInfo.alreadyUsedAmount) {
            uint256 fastAmount = stakingInfo.stakingAmount - stakingInfo.alreadyUsedAmount;
            if (fastAmount > _amount) {
                _unstakeAmount = _amount;
            } else {
                _unstakeAmount = fastAmount;
            }

            if (stakingInfo.isELRewardSharing) {
                settleElSharedReward(stakingInfo.operatorId);
                _updateShare(
                    _stakingId,
                    stakingInfo.operatorId,
                    stakingInfo.stakingAmount - stakingInfo.unstakeAmount,
                    _unstakeAmount,
                    false
                );
            }

            // _unstakeAmount is not equal to 0, which means that the unstake is completed synchronously
            stakingInfo.unstakeAmount += _unstakeAmount;
            stakingInfo.alreadyUsedAmount += _unstakeAmount;
            totalLargeStakeAmounts[stakingInfo.operatorId] -= _unstakeAmount;

            payable(stakingInfo.owner).transfer(_unstakeAmount);
            emit FastUnstake(_stakingId, _unstakeAmount);
        }

        stakingInfo.unstakeRequestAmount += _amount;

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
            settleElSharedReward(operatorId);
        }

        uint256 curStakingId;
        address elRewardPoolAddr;
        uint256 stakeAmounts = _pubKeys.length * 32 ether;
        (curStakingId, elRewardPoolAddr) =
            _stake(operatorId, _owner, _withdrawCredentials, _isELRewardSharing, stakeAmounts, true);
        for (uint256 i = 0; i < _pubKeys.length; ++i) {
            _savePubKey(curStakingId, operatorId, _pubKeys[i]);
        }
        totalLargeStakeAmounts[operatorId] += stakeAmounts;

        emit MigretaStake(operatorId, curStakingId, stakeAmounts, _owner, _withdrawCredentials, _isELRewardSharing);
    }

    function appendMigrateStake(
        uint256 _stakingId,
        address _owner,
        address _withdrawCredentials,
        bytes[] calldata _pubKeys
    ) public {
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        bytes32 userWithdrawalCredentials = getWithdrawCredentials(_withdrawCredentials);

        if (stakingInfo.owner != _owner || stakingInfo.withdrawCredentials != userWithdrawalCredentials) {
            revert InvalidParameter();
        }

        uint256 stakeAmounts = _pubKeys.length * 32 ether;

        if (stakingInfo.isELRewardSharing) {
            settleElSharedReward(stakingInfo.operatorId);
            _updateShare(
                _stakingId,
                stakingInfo.operatorId,
                stakingInfo.stakingAmount - stakingInfo.unstakeAmount,
                stakeAmounts,
                true
            );
        }

        largeStakingList[_stakingId].stakingAmount += stakeAmounts;
        largeStakingList[_stakingId].alreadyUsedAmount += stakeAmounts;
        totalLargeStakeAmounts[stakingInfo.operatorId] += stakeAmounts;

        for (uint256 i = 0; i < _pubKeys.length; ++i) {
            _savePubKey(_stakingId, stakingInfo.operatorId, _pubKeys[i]);
        }

        emit AppendMigretaStake(_stakingId, stakeAmounts);
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

        uint256 curStakingId = largeStakingList.length;

        bytes32 userWithdrawalCredentials = getWithdrawCredentials(_withdrawCredentials);
        largeStakingList.push(
            StakingInfo({
                isELRewardSharing: _isELRewardSharing,
                stakingId: curStakingId,
                operatorId: _operatorId,
                stakingAmount: _stakingAmount,
                alreadyUsedAmount: isMigrate ? _stakingAmount : 0,
                unstakeRequestAmount: 0,
                unstakeAmount: 0,
                owner: _owner,
                withdrawCredentials: userWithdrawalCredentials
            })
        );

        address elRewardPoolAddr;
        if (!_isELRewardSharing) {
            elRewardPoolAddr = elRewardFactory.create(_operatorId, address(this));
            elPrivateRewardPool[curStakingId] = elRewardPoolAddr;
        } else {
            elRewardPoolAddr = elSharedRewardPool[_operatorId];
            if (address(0) == elRewardPoolAddr) revert SharedRewardPoolNotOpened();

            _updateShare(curStakingId, _operatorId, 0, _stakingAmount, true);
        }

        return (curStakingId, elRewardPoolAddr);
    }

    function _updateShare(
        uint256 _stakingId,
        uint256 _operatorId,
        uint256 _curAmount,
        uint256 _updataAmount,
        bool _isStake
    ) internal {
        SettleInfo storage info = eLSharedRewardSettleInfo[_stakingId];

        info.rewardBalance += (valuePerShare[_operatorId] - info.valuePerSharePoint) * (_curAmount) / UNIT;
        info.valuePerSharePoint = valuePerShare[_operatorId];

        if (_isStake) {
            totalShares[_operatorId] += _updataAmount;
        } else {
            totalShares[_operatorId] -= _updataAmount;
        }
    }

    function getWithdrawCredentials(address _withdrawCredentials) public pure returns (bytes32) {
        return abi.decode(abi.encodePacked(hex"010000000000000000000000", _withdrawCredentials), (bytes32));
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
        if ((stakingInfo.stakingAmount - stakingInfo.alreadyUsedAmount) < depositAmount) {
            revert InsufficientFunds();
        }

        for (uint256 i = 0; i < _pubkeys.length; ++i) {
            depositContract.deposit{value: 32 ether}(
                _pubkeys[i], abi.encodePacked(stakingInfo.withdrawCredentials), _signatures[i], _depositDataRoots[i]
            );
            emit ValidatorRegistered(operatorId, _stakingId, _pubkeys[i]);
            _savePubKey(_stakingId, operatorId, _pubkeys[i]);
        }

        largeStakingList[_stakingId].alreadyUsedAmount += depositAmount;
    }

    function _savePubKey(uint256 _stakingId, uint256 _operatorId, bytes memory _pubkey) internal {
        validators[_stakingId].push(_pubkey);
        validatorOfOperator[_pubkey] = _operatorId;
    }

    function reward(uint256 _stakingId) public view returns (uint256 userReward) {
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        (uint256 operatorId,, uint256 rewards) = getRewardPoolInfo(_stakingId);

        if (stakingInfo.isELRewardSharing) {
            SettleInfo memory settleInfo = eLSharedRewardSettleInfo[_stakingId];
            userReward = settleInfo.rewardBalance;

            if (totalShares[operatorId] == 0 || valuePerShare[operatorId] == settleInfo.valuePerSharePoint) {
                return (userReward);
            }

            uint256 unsettledPoolReward;
            if (rewards != 0) {
                (,, unsettledPoolReward) = _calcElReward(rewards, operatorId);
            }

            uint256 unsettledUserReward = (
                valuePerShare[operatorId] + unsettledPoolReward * UNIT / totalShares[operatorId]
                    - settleInfo.valuePerSharePoint
            ) * (stakingInfo.stakingAmount - stakingInfo.unstakeAmount) / UNIT;
            userReward += unsettledUserReward;
        } else {
            userReward =
                unclaimedPrivateRewards[_stakingId] - daoPrivateRewards[_stakingId] - operatorPrivateRewards[_stakingId];
            if (rewards != 0) {
                (,, uint256 unsettledPoolReward) = _calcElReward(rewards, operatorId);
                userReward += unsettledPoolReward;
            }
        }

        return (userReward);
    }

    function getRewardPoolInfo(uint256 _stakingId)
        public
        view
        returns (uint256 operatorId, address rewardPoolAddr, uint256 rewards)
    {
        StakingInfo memory stakingInfo = largeStakingList[_stakingId];
        operatorId = stakingInfo.operatorId;
        if (stakingInfo.isELRewardSharing) {
            rewardPoolAddr = elSharedRewardPool[operatorId];
            rewards = rewardPoolAddr.balance - unclaimedSharedRewards[operatorId];
        } else {
            rewardPoolAddr = elPrivateRewardPool[_stakingId];
            rewards = rewardPoolAddr.balance - unclaimedPrivateRewards[_stakingId];
        }
        return (operatorId, rewardPoolAddr, rewards);
    }

    function settleElSharedReward(uint256 _operatorId) public {
        address rewardPoolAddr = elSharedRewardPool[_operatorId];
        uint256 rewards = rewardPoolAddr.balance - unclaimedSharedRewards[_operatorId];

        (uint256 daoReward, uint256 operatorReward, uint256 poolReward) = _calcElReward(rewards, _operatorId);
        if (poolReward == 0 || totalShares[_operatorId] == 0) return;

        operatorSharedRewards[_operatorId] += operatorReward;
        daoSharedRewards[_operatorId] += daoReward;
        unclaimedSharedRewards[_operatorId] = rewardPoolAddr.balance;

        valuePerShare[_operatorId] += poolReward * UNIT / totalShares[_operatorId]; // settle

        emit ELShareingRewardSettle(_operatorId, daoReward, operatorReward, poolReward);
    }

    function settleElPrivateReward(uint256 _stakingId) public {
        address rewardPoolAddr = elPrivateRewardPool[_stakingId];
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

        SettleInfo storage settleInfo = eLSharedRewardSettleInfo[_stakingId];

        address rewardPoolAddr;
        if (stakingInfo.isELRewardSharing) {
            settleElSharedReward(stakingInfo.operatorId);

            rewardPoolAddr = elSharedRewardPool[stakingInfo.operatorId];

            uint256 totalRewards = settleInfo.rewardBalance
                + (valuePerShare[stakingInfo.operatorId] - settleInfo.valuePerSharePoint)
                    * (stakingInfo.stakingAmount - stakingInfo.unstakeAmount) / UNIT;

            settleInfo.valuePerSharePoint = valuePerShare[stakingInfo.operatorId];

            settleInfo.rewardBalance = totalRewards - rewards;
            unclaimedSharedRewards[stakingInfo.operatorId] -= rewards;
        } else {
            settleElPrivateReward(_stakingId);
            rewardPoolAddr = elPrivateRewardPool[_stakingId];
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
            _distributeOperatorRewards(elPrivateRewardPool[stakingId], operatorRewards, stakingInfo.operatorId);
        }

        if (_claimSharePool) {
            (pledgeBalance, requirBalance) = nodeOperatorRegistryContract.getPledgeInfoOfOperator(_operatorId);
            if (pledgeBalance < requirBalance) revert InsufficientMargin();
            settleElSharedReward(_operatorId);
            uint256 operatorRewards = operatorSharedRewards[_operatorId];
            operatorSharedRewards[_operatorId] = 0;
            unclaimedSharedRewards[_operatorId] -= operatorRewards;
            emit OperatorSharedRewardClaimed(stakingInfo.operatorId, operatorRewards);
            _distributeOperatorRewards(elSharedRewardPool[_operatorId], operatorRewards, _operatorId);
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

            IELReward(elPrivateRewardPool[stakingId]).transfer(daoRewards, daoVaultAddress);
            emit DaoPrivateRewardClaimed(stakingId, daoVaultAddress, daoRewards);
        }

        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 operatorId = _operatorIds[i];
            settleElSharedReward(operatorId);
            uint256 daoRewards = daoSharedRewards[operatorId];
            daoSharedRewards[operatorId] = 0;
            unclaimedSharedRewards[operatorId] -= daoRewards;

            IELReward(elSharedRewardPool[operatorId]).transfer(daoRewards, daoVaultAddress);
            emit DaoSharedRewardClaimed(operatorId, daoVaultAddress, daoRewards);
        }
    }

    function reportCLStakingData(CLStakingInfo[] memory _clStakingInfo, CLStakingSlashInfo[] memory _clStakingSlashInfo)
        external
        onlyConsensusOracle
    {
        StakingInfo memory stakingInfo;
        for (uint256 i = 0; i < _clStakingInfo.length; ++i) {
            CLStakingInfo memory sInfo = _clStakingInfo[i];

            if (
                sInfo.notReportedUnstakeAmount % 32 ether != 0 || sInfo.stakingId > largeStakingList.length
                    || validatorOfOperator[sInfo.pubkey] == 0 || validatorExitReportBlock[sInfo.pubkey] != 0
            ) {
                revert InvalidReport();
            }
            validatorExitReportBlock[sInfo.pubkey] = block.number;

            stakingInfo = largeStakingList[sInfo.stakingId];
            uint256 newUnstakeAmount = stakingInfo.unstakeAmount + sInfo.notReportedUnstakeAmount;
            if (newUnstakeAmount > stakingInfo.stakingAmount) revert InvalidReport();

            if (stakingInfo.isELRewardSharing) {
                settleElSharedReward(stakingInfo.operatorId);
                _updateShare(
                    sInfo.stakingId,
                    stakingInfo.operatorId,
                    stakingInfo.stakingAmount - stakingInfo.unstakeAmount,
                    sInfo.notReportedUnstakeAmount,
                    false
                );
            }

            largeStakingList[sInfo.stakingId].unstakeAmount = newUnstakeAmount;
            // The operator actively withdraws from the validator
            if (newUnstakeAmount > stakingInfo.unstakeRequestAmount) {
                // When unstakeRequestAmount > unstakeAmount, the operator will exit the validator
                largeStakingList[sInfo.stakingId].unstakeRequestAmount = newUnstakeAmount;
            }

            totalLargeStakeAmounts[stakingInfo.operatorId] -= sInfo.notReportedUnstakeAmount;
            emit ValidatorExitReport(stakingInfo.operatorId, sInfo.notReportedUnstakeAmount);
        }

        uint256[] memory _stakingIds = new uint256[] (_clStakingSlashInfo.length);
        uint256[] memory _operatorIds = new uint256[] (_clStakingSlashInfo.length);
        uint256[] memory _amounts = new uint256[] (_clStakingSlashInfo.length);
        for (uint256 i = 0; i < _clStakingSlashInfo.length; ++i) {
            CLStakingSlashInfo memory sInfo = _clStakingSlashInfo[i];
            if (
                validatorOfOperator[sInfo.pubkey] == 0 || validatorSlashAmount[sInfo.pubkey] != 0
                    || sInfo.stakingId > largeStakingList.length - 1
            ) {
                revert InvalidReport();
            }

            _stakingIds[i] = sInfo.stakingId;
            _operatorIds[i] = largeStakingList[sInfo.stakingId].operatorId;
            _amounts[i] = sInfo.slashAmount;
            validatorSlashAmount[sInfo.pubkey] = sInfo.slashAmount;
        }

        if (_clStakingSlashInfo.length != 0) {
            operatorSlashContract.slashOperatorOfLargeStaking(_stakingIds, _operatorIds, _amounts);
            emit LargeStakingSlash(_stakingIds, _operatorIds, _amounts);
        }
    }

    function getOperatorValidatorCounts(uint256 _operatorId) external view returns (uint256) {
        return totalLargeStakeAmounts[_operatorId] / 32 ether;
    }

    function getLargeStakingListLength() public view returns (uint256) {
        return largeStakingList.length;
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
