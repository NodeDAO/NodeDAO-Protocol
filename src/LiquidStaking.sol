// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INETH.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/IDepositContract.sol";
import "src/interfaces/IWithdrawOracle.sol";
import "src/interfaces/IELVault.sol";
import {ERC721A__IERC721ReceiverUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import "src/interfaces/IConsensusVault.sol";
import "src/interfaces/IVaultManager.sol";

/**
 * @title NodeDao LiquidStaking Contract
 *
 * NodeDao is a DAO that provides decentralized solutions for Ethereum liquidity,
 * jointly initiated by ChainUp Cloud, XHash, AntAlpha, ImToken, and Bitrise.
 *
 * The NodeDAO protocol is a smart contract for next-generation liquid staking derivatives,
 * which includes all the concepts of traditional liquid staking, re-staking, distributed validators, and validator NFTs in a single protocol.
 *
 * Our vision is to use our innovative liquidity solution to provide more options for the Ethereum liquidity market,
 * thereby making Ethereum staking more decentralized.
 */

contract LiquidStaking is
    ILiquidStaking,
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC721A__IERC721ReceiverUpgradeable
{
    IDepositContract public depositContract;

    INodeOperatorsRegistry public nodeOperatorRegistryContract;

    INETH public nETHContract;

    IVNFT public vNFTContract;

    IWithdrawOracle public beaconOracleContract;

    bytes public liquidStakingWithdrawalCredentials;

    // deposit fee rate
    uint256 public depositFeeRate;
    uint256 internal constant totalBasisPoints = 10000;

    uint256 internal constant DEPOSIT_SIZE = 32 ether;
    // After the Shanghai upgrade, the rewards will be distributed linearly,
    // and the rewards will not exceed 16ETH, so the maximum value of a node is set to 48ETH
    uint256 internal constant MAX_NODE_VALUE = 48 ether;

    // operator's internal stake pool, key is operator_id
    mapping(uint256 => uint256) public operatorPoolBalances;

    // unused funds in the current liquidStaking pool
    uint256 internal operatorPoolBalancesSum;

    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;

    // v2 storage

    address public vaultManagerContractAddress;
    IConsensusVault public consensusVaultContract;

    // operator's internal nft stake pool, key is operator_id
    mapping(uint256 => uint256) public operatorNftPoolBalances;

    struct StakeInfo {
        uint256 operatorId;
        uint256 quota;
    }

    // key is user address, value is StakeInfo
    mapping(address => StakeInfo[]) internal stakeRecords;

    // key is quit operatorId, value is asign operatorId
    mapping(uint256 => uint256) public reAssignRecords;

    uint256 public operatorCanLoanAmounts;

    // key is operatorId, value is loan amounts
    mapping(uint256 => uint256) public operatorLoanRecords;
    // key is operatorId, value is loan blockNumber
    mapping(uint256 => uint256) public operatorLoadBlockNumbers;
    // key is tokenId, value is nft unstake blocknumber
    mapping(uint256 => uint256) internal nftUnstakeBlockNumbers;

    // key is operatorId, value is operator unstake tokenid lists
    mapping(uint256 => uint256[]) internal operatorUnstakeNftLists;

    // When nft is punished by the network,
    //   for the user's nft, the penalty amount should be given to the user
    // When the operator margin is insufficient, how much compensation is owed will be recorded
    // key is tokenId, value is nft compensated
    mapping(uint256 => uint256) public nftWillCompensated;
    // Compensation already paid
    mapping(uint256 => uint256) public nftHasCompensated;
    // Record the set of tokenids that the operator will compensate
    mapping(uint256 => uint256[]) public operatorSlashArrears;
    // The index of the compensation that has been completed is used for the distribution of compensation when replenishing the margin
    uint256 public operatorCompensatedIndex;

    // delay exit slash
    // When the operator does not nft unstake or large withdrawals for more than 72 hours, the oracle will be punished
    uint256 public delayedExitSlashStandard;
    // Penalty amount for each validator per block
    uint256 public slashAmountPerBlockPerValidator;

    // Record the latest penalty information
    // key is tokenId, value is blockNumber
    mapping(uint256 => uint256) public nftExitDelayedSlashRecords;
    // key is requestId, value is blockNumber
    mapping(uint256 => uint256) public largeExitDelayedSlashRecords;

    // large withdrawals request
    uint256 public constant MIN_NETH_WITHDRAWAL_AMOUNT = 32 * 1e18;
    uint256 public constant MAX_NETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;

    // For large withdrawals, the withdrawn Neth will be locked in the liquid contract and wait for the user to claim to complete the burning
    uint256 public totalLockedNethBalance;
    // The total amount of requests for large withdrawals by the operator
    mapping(uint256 => uint256) public operatorPendingEthRequestAmount;
    // Repay the pool amount for large withdrawals
    mapping(uint256 => uint256) public operatorPendingEthPoolBalance;

    struct WithdrawalInfo {
        uint256 operatorId;
        uint256 withdrawHeight;
        uint256 withdrawNethAmount;
        uint256 withdrawExchange;
        uint256 claimEthAmount;
        address owner;
        bool isClaim;
    }

    // For large withdrawal requests, it is allowed to claim out of queue order
    WithdrawalInfo[] public withdrawalQueues;

    modifier onlyDao() {
        require(msg.sender == dao, "PERMISSION_DENIED");
        _;
    }

    modifier onlyVaultManager() {
        require(msg.sender == vaultManagerContractAddress, "PERMISSION_DENIED");
        _;
    }

    /**
     * @notice initialize LiquidStaking Contract
     * @param _dao Dao contract address
     * @param _daoVaultAddress Dao Vault Address
     * @param _withdrawalCreds Withdrawal Credentials, Withdrawal vault contract address
     * @param _nodeOperatorRegistryContractAddress Node Operator Registry Contract Address
     * @param _nETHContractAddress NETH contract address, The liquidity token for the eth stake
     * @param _nVNFTContractAddress VNFT contract address, The NFT representing the validator
     * @param _beaconOracleContractAddress Beacon Oracle Contract Address, where balances and VNFT values are tracked
     * @param _depositContractAddress eth2 Deposit Contract Address
     */
    function initialize(
        address _dao,
        address _daoVaultAddress,
        bytes memory _withdrawalCreds,
        address _nodeOperatorRegistryContractAddress,
        address _nETHContractAddress,
        address _nVNFTContractAddress,
        address _beaconOracleContractAddress,
        address _depositContractAddress
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        dao = _dao;
        daoVaultAddress = _daoVaultAddress;

        liquidStakingWithdrawalCredentials = _withdrawalCreds;

        depositContract = IDepositContract(_depositContractAddress);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContractAddress);

        nETHContract = INETH(_nETHContractAddress);

        vNFTContract = IVNFT(_nVNFTContractAddress);

        beaconOracleContract = IWithdrawOracle(_beaconOracleContractAddress);
    }

    /**
     * @notice initializeV2 LiquidStaking Contract
     * @param _operatorIds operator id
     * @param _users user Address
     * @param _nethAmounts Withdrawal Credentials, Withdrawal vault contract address
     */
    function initializeV2(uint256[] memory _operatorIds, address[] memory _users, uint256[] memory _nethAmounts) public reinitializer(2) onlyDao {
        // merge already stake data to StakeRecords
        require(_operatorIds.length == _users.length && _nethAmounts.length == _users.length, "invalid parameter");
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            require(nodeOperatorRegistryContract.isTrustedOperator(_operatorIds[i]), "The operator is not trusted");
            _stake(_operatorIds[i], _users[i], _nethAmounts[i]);
        }

        // mainnet 50400; goerli 7200
        delayedExitSlashStandard = 7200;
        slashAmountPerBlockPerValidator = 2000000000000;
        operatorCanLoanAmounts = 32 ether;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice For operators added to the blacklist by dao, for example,
     * because the operator has been inactive for a long time,
     * and has been punished on a large scale, etc.
     *
     * The Dao has the right to distribute the available balance on this operator to other active operators,
     * and the allocation share will be determined through proposals
     * @param _assignOperatorId blacklist operator id
     * @param _operatorId The operator id of the allocation share
     */
    function assignBlacklistOperator(uint256 _assignOperatorId, uint256 _operatorId) external onlyOwner {
        // assignOperatorId must be a blacklist operator
        require(nodeOperatorRegistryContract.isBlacklistOperator(_assignOperatorId), "The assign operator is trusted");
        require(nodeOperatorRegistryContract.isTrustedOperator(_operatorId), "The operator is not trusted");

        uint256 assignOperatorBalances = _assignOperator(_assignOperatorId, _operatorId);

        emit BlacklistOperatorAssigned(_assignOperatorId, _operatorId, assignOperatorBalances);
    }

    /**
     * @notice for exiting operator
     * The Dao has the right to distribute the available balance of this operator to other active operators,
     * Allocation share will be determined by proposal
     * @param _quitOperatorId quit operator id
     * @param _operatorId The operator id of the allocation share
     */
    function assignQuitOperator(uint256 _quitOperatorId, uint256 _operatorId) external onlyOwner {
        // _quitOperatorId must be a quit operator
        require(nodeOperatorRegistryContract.isQuitOperator(_quitOperatorId), "The assign operator did not exit");
        require(nodeOperatorRegistryContract.isTrustedOperator(_operatorId), "The operator is not trusted");

        if (reAssignRecords[_quitOperatorId] != 0) {
            require(reAssignRecords[_quitOperatorId] == _operatorId, "already assigned");
        }
        uint256 assignOperatorBalances = _assignOperator(_quitOperatorId, _operatorId);
        reAssignRecords[_quitOperatorId] = _operatorId;

        emit QuitOperatorAssigned(_quitOperatorId, _operatorId, assignOperatorBalances);
    }

    function _assignOperator(uint256 _assignOperatorId, uint256 _operatorId) internal returns (uint256) {
        uint256 assignOperatorBalances = operatorPoolBalances[_assignOperatorId];
        uint256 loanAmounts = operatorLoanRecords[_assignOperatorId];
        if (loanAmounts > 0) {
            if (loanAmounts > assignOperatorBalances) {
                operatorLoanRecords[_assignOperatorId] -= assignOperatorBalances;
                assignOperatorBalances = 0;
            } else {
                operatorLoanRecords[_assignOperatorId] = 0;
                assignOperatorBalances -= loanAmounts;
            }
        }

        operatorPoolBalances[_operatorId] += assignOperatorBalances;
        operatorPoolBalances[_assignOperatorId] = 0;

        return assignOperatorBalances;
    }

    /**
     * @notice stake eth to designated operator, stake ETH to get nETH
     * @param _operatorId operator id
     */
    function stakeETH(uint256 _operatorId) external payable nonReentrant whenNotPaused {
        require(msg.value >= 1000 gwei, "Stake amount must be minimum 1000 gwei");

        // operatorId must be a trusted operator
        require(nodeOperatorRegistryContract.isTrustedOperator(_operatorId), "The operator is not trusted");

        // Must meet the basic mortgage funds before being allowed to be entrusted
        require(nodeOperatorRegistryContract.isConformBasicPledge(_operatorId), "Insufficient pledge balance");

        // When the deposit rate is not 0, charge the fee
        uint256 depositFeeAmount;
        uint256 depositPoolAmount;
        if (depositFeeRate == 0) {
            depositPoolAmount = msg.value;
        } else {
            depositFeeAmount = msg.value * depositFeeRate / totalBasisPoints;
            depositPoolAmount = msg.value - depositFeeAmount;
            require(daoVaultAddress != address(0), "DaoVaultAddress address invalid");
            payable(daoVaultAddress).transfer(depositFeeAmount);
            emit Transferred(daoVaultAddress, depositFeeAmount);
        }

        // 1. Convert depositAmount according to the exchange rate of nETH
        // 2. Mint nETH
        uint256 amountOut = getNethOut(depositPoolAmount);
        nETHContract.whiteListMint(amountOut, msg.sender);

        _updateStakeFundLedger(_operatorId, depositPoolAmount);
        _stake(_operatorId, msg.sender, amountOut);

        emit EthStake(_operatorId, msg.sender, msg.value, amountOut);
    }

    function _updateStakeFundLedger(uint256 _operatorId, uint256 _amount) internal {
        operatorPoolBalancesSum += _amount;

        uint256 loanAmounts = operatorLoanRecords[_operatorId];
        if (loanAmounts > 0) {
            if (loanAmounts > _amount) {
                operatorLoanRecords[_operatorId] -= _amount;
                _amount = 0;
            } else {
                operatorLoanRecords[_operatorId] = 0;
                operatorLoadBlockNumbers[_operatorId] = 0;
                _amount = _amount - loanAmounts;
            }
        }

        if (_amount > 0) {
            operatorPoolBalances[_operatorId] += _amount;
        }
    }

    function _stake(uint256 _operatorId, address _from, uint256 _amount) internal {
        StakeInfo[] memory records = stakeRecords[_from];
        if (records.length == 0) {
            stakeRecords[_from].push(StakeInfo({operatorId: _operatorId, quota: _amount}));
        } else {
            for (uint256 i = 0; i < records.length; ++i) {
                if (records[i].operatorId == _operatorId) {
                    stakeRecords[_from][i].quota += _amount;
                    return;
                }
            }

            stakeRecords[_from].push(StakeInfo({operatorId: _operatorId, quota: _amount}));
        }
    }

    /**
     * @notice unstake neth to designated operator
     * @param _operatorId operator id
     * @param _amounts untake neth amount
     */
    function unstakeETH(uint256 _operatorId, uint256 _amounts) public nonReentrant whenNotPaused {
        uint256 amountOut = getEthOut(_amounts);

        _unstake(_operatorId, msg.sender, _amounts);

        uint256 targetOperatorId = _updateUnstakeFundLedger(amountOut, _operatorId);

        nETHContract.whiteListBurn(_amounts, msg.sender);
        payable(msg.sender).transfer(amountOut);

        emit EthUnstake(_operatorId, targetOperatorId, msg.sender, _amounts, amountOut);
    }

    function _unstake(uint256 _operatorId, address _from, uint256 _amount) internal {
        StakeInfo[] memory records = stakeRecords[_from];
        require(records.length != 0, "No unstake quota");
        for (uint256 i = 0; i < records.length; ++i) {
            if (records[i].operatorId == _operatorId) {
                require(stakeRecords[_from][i].quota >= _amount, "Insufficient unstake quota");
                stakeRecords[_from][i].quota -= _amount;
                return;
            }
        }

        require(false, "No unstake quota");
    }

    function _updateUnstakeFundLedger(uint256 _ethOutAmount, uint256 _operatorId) internal returns (uint256) {
        uint256 targetOperatorId = _operatorId;
        bool isQuit = nodeOperatorRegistryContract.isQuitOperator(_operatorId);
        if (isQuit) {
            uint256 reAssignOperatorId = reAssignRecords[_operatorId];
            if (reAssignOperatorId != 0) {
                targetOperatorId = reAssignOperatorId;
            }
        }

        uint256 operatorBalances = operatorPoolBalances[targetOperatorId];
        if (operatorBalances >= _ethOutAmount) {
            operatorPoolBalances[targetOperatorId] -= _ethOutAmount;
        } else {
            require(!isQuit || (targetOperatorId != _operatorId), "No loan eligibility");
            uint256 newLoanAmounts = _ethOutAmount - operatorBalances;
            uint256 operatorLoanAmounts = operatorLoanRecords[targetOperatorId];
            require((operatorCanLoanAmounts > operatorLoanAmounts + newLoanAmounts), "Insufficient funds to unstake");
            operatorPoolBalances[targetOperatorId] = 0;
            operatorLoanRecords[targetOperatorId] += newLoanAmounts;
            if (operatorLoadBlockNumbers[targetOperatorId] != 0) {
                operatorLoadBlockNumbers[targetOperatorId] = block.number;
            }
        }

        operatorPoolBalancesSum -= _ethOutAmount;

        return targetOperatorId;
    }

    /**
     * @notice Stake 32 multiples of eth to get the corresponding number of vNFTs
     * @param _operatorId operator id
     */
    function stakeNFT(uint256 _operatorId, address withdrawalCredentialsAddress)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(withdrawalCredentialsAddress != address(0), "withdrawalCredentialsAddress is an invalid address");

        // operatorId must be a trusted operator
        require(nodeOperatorRegistryContract.isTrustedOperator(_operatorId), "The operator is not trusted");
        require(msg.value % DEPOSIT_SIZE == 0, "Incorrect Ether amount");

        // Must meet the basic mortgage funds before being allowed to be entrusted
        require(nodeOperatorRegistryContract.isConformBasicPledge(_operatorId), "Insufficient pledge balance");

        bytes memory userWithdrawalCredentials =
            bytes.concat(hex"010000000000000000000000", abi.encodePacked(withdrawalCredentialsAddress));

        uint256 mintNftsCount = msg.value / DEPOSIT_SIZE;
        for (uint256 i = 0; i < mintNftsCount; ++i) {
            uint256 tokenId = vNFTContract.whiteListMint(bytes(""), userWithdrawalCredentials, msg.sender, _operatorId);
        }

        operatorNftPoolBalances[_operatorId] += msg.value;

        emit NftStake(_operatorId, msg.sender, mintNftsCount);
    }

    /**
     * @notice Perform unstake operation on the held nft, an irreversible operation, and get back the pledged deth
     * @param _tokenIds unstake token id
     */
    function unstakeNFT(uint256[] calldata _tokenIds) external nonReentrant whenNotPaused {
        uint256[] memory operatorIds = new uint256[] (1);
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            require(nftUnstakeBlockNumbers[tokenId] == 0, "The tokenId already unstake");
            require(msg.sender == vNFTContract.ownerOf(tokenId), "The sender must be the nft owner");

            uint256 operatorId = vNFTContract.operatorOf(tokenId);
            operatorIds[0] = operatorId;
            IVaultManager(vaultManagerContractAddress).settleAndReinvestElReward(operatorIds);

            bytes memory pubkey = vNFTContract.validatorOf(tokenId);
            if (keccak256(pubkey) == keccak256(bytes(""))) {
                operatorNftPoolBalances[operatorId] -= DEPOSIT_SIZE;
                payable(msg.sender).transfer(DEPOSIT_SIZE);
                emit Transferred(msg.sender, DEPOSIT_SIZE);
                vNFTContract.whiteListBurn(tokenId);
            } else {
                nftUnstakeBlockNumbers[tokenId] = block.number;
                operatorUnstakeNftLists[operatorId].push(tokenId);
            }

            emit NftUnstake(operatorId, tokenId);
        }
    }

    /**
     * @notice Large withdrawal request, used for withdrawals over 32neth and less than 1000 neth.
     * @param _operatorId operator id
     * @param _amounts untake neth amount
     */
    function requestLargeWithdrawals(uint256 _operatorId, uint256[] calldata _amounts)
        public
        nonReentrant
        whenNotPaused
    {
        uint256 totalRequestNethAmount = 0;
        uint256 totalPendingEthAmount = 0;

        uint256 _exchange = getEthOut(1 ether);
        for (uint256 i = 0; i < _amounts.length; ++i) {
            uint256 _amount = _amounts[i];
            require(
                _amount >= MIN_NETH_WITHDRAWAL_AMOUNT && _amount <= MAX_NETH_WITHDRAWAL_AMOUNT, "invalid request amount"
            );

            uint256 amountOut = getEthOut(_amount);
            withdrawalQueues.push(
                WithdrawalInfo({
                    operatorId: _operatorId,
                    withdrawHeight: block.number,
                    withdrawNethAmount: _amount,
                    withdrawExchange: _exchange,
                    claimEthAmount: amountOut,
                    owner: msg.sender,
                    isClaim: false
                })
            );

            totalRequestNethAmount += _amount;
            totalPendingEthAmount += amountOut;
        }

        bool success = nETHContract.transferFrom(msg.sender, address(this), totalRequestNethAmount);
        require(success, "Failed to transfer neth");

        _unstake(_operatorId, msg.sender, totalRequestNethAmount);
        totalLockedNethBalance += totalRequestNethAmount;
        operatorPendingEthRequestAmount[_operatorId] += totalPendingEthAmount;

        emit LargeWithdrawalsRequest(_operatorId, msg.sender, totalRequestNethAmount);
    }

    function claimLargeWithdrawals(uint256[] calldata requestIds) public nonReentrant whenNotPaused {
        uint256 totalRequestNethAmount = 0;
        uint256 totalPendingEthAmount = 0;

        for (uint256 i = 0; i < requestIds.length; ++i) {
            uint256 id = requestIds[i];
            WithdrawalInfo memory wInfo = withdrawalQueues[id];
            require(wInfo.owner == msg.sender, "no permission");
            require(!wInfo.isClaim, "requestId already claimed");
            withdrawalQueues[id].isClaim = true;
            totalRequestNethAmount += wInfo.withdrawNethAmount;
            totalPendingEthAmount += wInfo.claimEthAmount;
            operatorPendingEthRequestAmount[wInfo.operatorId] -= wInfo.claimEthAmount;
            operatorPendingEthPoolBalance[wInfo.operatorId] -= wInfo.claimEthAmount;
        }

        nETHContract.whiteListBurn(totalRequestNethAmount, address(this));
        totalLockedNethBalance -= totalRequestNethAmount;
        payable(msg.sender).transfer(totalPendingEthAmount);
    }

    /**
     * @notice registers validators
     * @param _pubkeys validator pubkeys
     * @param _signatures validator signatures
     * @param _depositDataRoots validator depositDataRoots
     */
    function registerValidator(
        bytes[] calldata _pubkeys,
        bytes[] calldata _signatures,
        bytes32[] calldata _depositDataRoots
    ) external nonReentrant whenNotPaused {
        require(
            _pubkeys.length == _signatures.length && _pubkeys.length == _depositDataRoots.length,
            "parameter must have the same length"
        );

        // must be a trusted operator
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        require(operatorId != 0, "The sender must be controlAddress of the trusted operator");
        require(
            (operatorPoolBalances[operatorId] + operatorNftPoolBalances[operatorId]) / DEPOSIT_SIZE >= _pubkeys.length,
            "Insufficient balance"
        );

        uint256 userValidatorNumber = 0;
        for (uint256 i = 0; i < _pubkeys.length; ++i) {
            uint256 count = _stakeAndMint(operatorId, _pubkeys[i], _signatures[i], _depositDataRoots[i]);
            userValidatorNumber += count;
        }

        uint256 stakeAmount = DEPOSIT_SIZE * _pubkeys.length;
        uint256 userStakeAmount = DEPOSIT_SIZE * userValidatorNumber;
        uint256 poolStakeAmount = stakeAmount - userStakeAmount;
        operatorPoolBalances[operatorId] -= poolStakeAmount;
        operatorPoolBalancesSum -= poolStakeAmount;
        if (userStakeAmount != 0) {
            operatorNftPoolBalances[operatorId] -= userStakeAmount;
        }

        beaconOracleContract.addPendingBalances(poolStakeAmount);
    }

    function _stakeAndMint(
        uint256 _operatorId,
        bytes calldata _pubkey,
        bytes calldata _signature,
        bytes32 _depositDataRoot
    ) internal returns (uint256) {
        bytes memory nextValidatorWithdrawalCredential = vNFTContract.getNextValidatorWithdrawalCredential(_operatorId);
        bytes memory _withdrawalCredential = (nextValidatorWithdrawalCredential.length != 0)
            ? nextValidatorWithdrawalCredential
            : liquidStakingWithdrawalCredentials;

        depositContract.deposit{value: 32 ether}(_pubkey, _withdrawalCredential, _signature, _depositDataRoot);

        uint256 tokenId = vNFTContract.whiteListMint(_pubkey, _withdrawalCredential, address(this), _operatorId);

        emit ValidatorRegistered(_operatorId, tokenId);

        if (nextValidatorWithdrawalCredential.length != 0) {
            return 1;
        }

        return 0;
    }

    /**
     * @notice Update the status of the corresponding nft according to the report result of the oracle machine
     * @param _tokenIds token id
     * @param _exitBlockNumbers exit block number
     */
    function nftExitHandle(uint256[] memory _tokenIds, uint256[] memory _exitBlockNumbers) external onlyVaultManager {
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            if (vNFTContract.ownerOf(tokenId) == address(this)) {
                vNFTContract.whiteListBurn(tokenId);
            }
        }

        vNFTContract.setNftExitBlockNumbers(_tokenIds, _exitBlockNumbers);
        emit NftExitBlockNumberSet(_tokenIds, _exitBlockNumbers);
    }

    /**
     * @notice According to the settlement results of the vaultManager, the income of the re-investment execution layer
     * @param _operatorIds operator id
     * @param _amounts reinvest amounts
     */
    function reinvestElRewards(uint256[] memory _operatorIds, uint256[] memory _amounts) external onlyVaultManager {
        require(_operatorIds.length == _amounts.length, "invalid length");
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 operatorId = _operatorIds[i];
            uint256 _amount = _amounts[i];
            if (_amount == 0) {
                continue;
            }

            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
            IELVault(vaultContractAddress).reinvestment(_amount);

            _updateStakeFundLedger(operatorId, _amount);
            emit OperatorReinvestElRewards(operatorId, _amount);
        }
    }

    /**
     * @notice According to the reported results of the oracle machine, the income of the consensus layer is re-invested
     * @param _operatorIds operator id
     * @param _amounts reinvest amounts
     */
    function reinvestClRewards(uint256[] memory _operatorIds, uint256[] memory _amounts) external onlyVaultManager {
        require(_operatorIds.length == _amounts.length, "invalid length");
        uint256 totalReinvestRewards = 0;
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 operatorId = _operatorIds[i];
            uint256 _amount = _amounts[i];
            if (_amount == 0) {
                continue;
            }
            totalReinvestRewards += _amount;

            uint256 operatorPendingPool = operatorPendingEthPoolBalance[operatorId];
            uint256 operatorPendingRequestAmount = operatorPendingEthRequestAmount[operatorId];
            if (operatorPendingPool < operatorPendingRequestAmount) {
                if (operatorPendingPool + _amount >= operatorPendingRequestAmount) {
                    operatorPendingEthPoolBalance[operatorId] = operatorPendingRequestAmount;
                    _amount = _amount - (operatorPendingRequestAmount - operatorPendingPool);
                } else {
                    operatorPendingEthPoolBalance[operatorId] += _amount;
                    _amount = 0;
                }
            }
            if (_amount != 0) {
                _updateStakeFundLedger(operatorId, _amount);
                emit OperatorReinvestClRewards(operatorId, _amount);
            }
        }

        consensusVaultContract.reinvestment(totalReinvestRewards);
    }

    /**
     * @notice According to the report results of the oracle machine, the operator who has reduced nft will be punished
     * @param _exitTokenIds token id
     * @param _amounts slash amounts
     */
    function slashOperator(uint256[] memory _exitTokenIds, uint256[] memory _amounts) external onlyVaultManager {
        require(_exitTokenIds.length == _amounts.length && _amounts.length != 0, "parameter invalid length");
        nodeOperatorRegistryContract.slash(_exitTokenIds, _amounts);
    }

    /**
     * @notice According to the report result of the oracle machine, punish the operator who fails to exit in time
     * @param _nftExitDelayedTokenIds exit delayed tokenIds
     * @param _largeExitDelayedRequestIds large exit delayed requestIds
     */
    function slashOfExitDelayed(uint256[] memory _nftExitDelayedTokenIds, uint256[] memory _largeExitDelayedRequestIds)
        external
        onlyVaultManager
    {
        for (uint256 i = 0; i < _nftExitDelayedTokenIds.length; ++i) {
            uint256 tokenId = _nftExitDelayedTokenIds[i];
            uint256 startNumber = nftUnstakeBlockNumbers[i];
            if (nftExitDelayedSlashRecords[tokenId] != 0) {
                startNumber = nftExitDelayedSlashRecords[tokenId];
            }

            nftExitDelayedSlashRecords[tokenId] = block.number;
            uint256 operatorId = vNFTContract.operatorOf(tokenId);

            _delaySlash(operatorId, startNumber, 1);
        }

        for (uint256 i = 0; i < _largeExitDelayedRequestIds.length; ++i) {
            uint256 requestId = _largeExitDelayedRequestIds[i];
            WithdrawalInfo memory wInfo = withdrawalQueues[requestId];
            uint256 startNumber = wInfo.withdrawHeight;
            if (largeExitDelayedSlashRecords[requestId] != 0) {
                startNumber = largeExitDelayedSlashRecords[requestId];
            }
            largeExitDelayedSlashRecords[requestId] = block.number;
            uint256 operatorId = wInfo.operatorId;
            _delaySlash(operatorId, startNumber, wInfo.claimEthAmount % 32 ether);
        }
    }

    function _delaySlash(uint256 _operatorId, uint256 _startNumber, uint256 validatorNumber) internal {
        uint256 slashNumber = block.number - _startNumber;
        require(slashNumber >= delayedExitSlashStandard, "does not qualify for slash");
        uint256 _amount = slashNumber * slashAmountPerBlockPerValidator * validatorNumber;
        nodeOperatorRegistryContract.slashOfExitDelayed(_operatorId, _amount);
    }

    /**
     * @notice Receive slash fund, Because the operator may have insufficient margin, _slashAmounts may be less than or equal to _requireAmounts
     * @param _exitTokenIds exit tokenIds
     * @param _slashAmounts slash amount
     * @param _requireAmounts require slas amount
     */
    function slashReceive(
        uint256[] memory _exitTokenIds,
        uint256[] memory _slashAmounts,
        uint256[] memory _requireAmounts
    ) external payable {
        require(msg.sender == address(nodeOperatorRegistryContract), "PERMISSION_DENIED");
        for (uint256 i = 0; i < _exitTokenIds.length; ++i) {
            uint256 tokenId = _exitTokenIds[i];
            uint256 operatorId = vNFTContract.operatorOf(tokenId);
            if (vNFTContract.ownerOf(tokenId) == address(this)) {
                _updateStakeFundLedger(operatorId, _slashAmounts[i]);
            } else {
                uint256 requirAmount = _requireAmounts[i];
                uint256 slashAmount = _slashAmounts[i];
                require(requirAmount >= slashAmount, "Abnormal slash amount");
                if (requirAmount != slashAmount) {
                    nftWillCompensated[tokenId] += requirAmount - slashAmount;
                    operatorSlashArrears[operatorId].push(tokenId);
                }
                nftHasCompensated[tokenId] += slashAmount;
            }

            emit SlashReceive(operatorId, tokenId, _slashAmounts[i], _requireAmounts[i]);
        }
    }

    /**
     * @notice The receiving function of the penalty, used for the automatic transfer after the operator recharges the margin
     * @param _operatorId operator Id
     * @param _amount slash amount
     */
    function slashArrearsReceive(uint256 _operatorId, uint256 _amount) external payable {
        emit ArrearsReceiveOfSlash(_operatorId, _amount);

        require(msg.sender == address(nodeOperatorRegistryContract), "PERMISSION_DENIED");
        uint256 compensatedIndex = operatorCompensatedIndex;
        while (
            operatorSlashArrears[_operatorId].length != 0
                && operatorSlashArrears[_operatorId].length - 1 != compensatedIndex
        ) {
            uint256 tokenId = operatorSlashArrears[_operatorId][compensatedIndex];
            uint256 arrears = nftWillCompensated[tokenId];
            if (_amount >= arrears) {
                nftWillCompensated[tokenId] = 0;
                nftHasCompensated[tokenId] += _amount;
                compensatedIndex += 1;
                _amount -= arrears;
            } else {
                nftWillCompensated[tokenId] -= _amount;
                nftHasCompensated[tokenId] += _amount;
                _amount = 0;
            }

            if (_amount == 0) {
                operatorCompensatedIndex = compensatedIndex;
                break;
            }
        }

        if (_amount != 0) {
            _updateStakeFundLedger(_operatorId, _amount);
        }
    }

    /**
     * @notice Can get a large amount of active withdrawal requests from an address
     * @param _owner _owner address
     */
    function getWithdrawalRequestIdOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 counts = 0;
        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].owner == _owner && !withdrawalQueues[i].isClaim) {
                counts += 1;
            }
        }

        uint256[] memory ids = new uint256[](counts);
        uint256 index = 0;
        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].owner == _owner && !withdrawalQueues[i].isClaim) {
                ids[index++] = i;
            }
        }

        return ids;
    }

    /**
     * @notice Obtain all large withdrawal requests of an operator
     * @param _operatorId operator Id
     */
    function getWithdrawalOfOperator(uint256 _operatorId) external view returns (WithdrawalInfo[] memory) {
        uint256 counts = 0;

        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].operatorId == _operatorId) {
                counts += 1;
            }
        }

        WithdrawalInfo[] memory wInfo = new WithdrawalInfo[](counts);
        uint256 wIndex = 0;
        for (uint256 i = 0; i < withdrawalQueues.length; ++i) {
            if (withdrawalQueues[i].operatorId == _operatorId) {
                wInfo[wIndex++] = withdrawalQueues[i];
            }
        }

        return wInfo;
    }

    /**
     * @notice Get the tokenid set that the user initiates to exit but the operator has not yet operated
     * @param _operatorId operator Id
     */
    function getUserUnstakeButOperatorNoExitNfs(uint256 _operatorId) external view returns (uint256[] memory) {
        uint256 counts = 0;
        uint256[] memory tokenIds = operatorUnstakeNftLists[_operatorId];
        uint256[] memory exitBlockNumbers = vNFTContract.getNftExitBlockNumbers(tokenIds);
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            if (exitBlockNumbers[i] == 0) {
                counts += 1;
            }
        }

        uint256[] memory noExitNfts = new uint256[] (counts);
        uint256 j = 0;
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            if (exitBlockNumbers[i] == 0) {
                noExitNfts[j++] = i;
            }
        }

        return noExitNfts;
    }

    /**
     * @notice Obtain the available amount that the user can unstake
     * @param _from user addresss
     */
    function getUnstakeQuota(address _from) public view returns (StakeInfo[] memory) {
        return stakeRecords[_from];
    }

    /**
     * @notice Obtain the unstake amount available for users under a certain operator
     * @param _operatorId operator Id
     */
    function getOperatorNethUnstakePoolAmounts(uint256 _operatorId) public view returns (uint256) {
        uint256 targetOperatorId = _operatorId;
        bool isQuit = nodeOperatorRegistryContract.isQuitOperator(_operatorId);
        if (isQuit) {
            uint256 reAssignOperatorId = reAssignRecords[_operatorId];
            if (reAssignOperatorId != 0) {
                targetOperatorId = reAssignOperatorId;
            }
        }

        uint256 operatorBalances = operatorPoolBalances[targetOperatorId];

        uint256 operatorLoanAmounts = operatorLoanRecords[targetOperatorId];

        if (operatorLoanAmounts >= operatorCanLoanAmounts) {
            return operatorBalances;
        }

        uint256 totalUnstakePoolAmounts = operatorBalances + operatorCanLoanAmounts - operatorLoanAmounts;
        if (totalUnstakePoolAmounts > operatorPoolBalancesSum) {
            return operatorPoolBalancesSum;
        }

        return totalUnstakePoolAmounts;
    }

    /**
     * @notice get nft unstake block number
     * @param _tokenId token id
     */
    function getNftUnstakeBlockNumber(uint256 _tokenId) public view returns (uint256) {
        return nftUnstakeBlockNumbers[_tokenId];
    }

    /**
     * @notice Users claim vNFT rewards
     * @dev There is no need to judge whether this nft belongs to the liquidStaking,
     *      because the liquidStaking cannot directly reward
     * @param _operatorId operator id
     * @param _tokenIds vNFT tokenIds
     * @param _amounts reward
     * @param _gasHeight update claim gasHeigt
     */
    function claimRewardsOfUser(
        uint256 _operatorId,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        uint256 _gasHeight
    ) external nonReentrant whenNotPaused onlyVaultManager {
        require(_tokenIds.length == _tokenIds.length && _amounts.length != 0, "parameter invalid length");
        require(_gasHeight <= block.number, "_gasHeight invalid");

        uint256[] memory exitBlockNumbers = vNFTContract.getNftExitBlockNumbers(_tokenIds);
        uint256 totalNftRewards = 0;
        address owner = vNFTContract.ownerOf(_tokenIds[0]);
        uint256 totalCompensated;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            require(owner == vNFTContract.ownerOf(tokenId), "different owners cannot batch");
            totalNftRewards += _amounts[i];

            if (exitBlockNumbers[i] != 0) {
                vNFTContract.whiteListBurn(tokenId);
            } else {
                vNFTContract.setUserNftGasHeight(tokenId, _gasHeight);
            }

            if (nftHasCompensated[tokenId] != 0) {
                totalCompensated += nftHasCompensated[tokenId];
                nftHasCompensated[tokenId] = 0;
            }
        }

        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
        IELVault(vaultContractAddress).transfer(totalNftRewards, owner);
        if (totalCompensated != 0) {
            payable(owner).transfer(totalCompensated);
        }

        emit UserClaimRewards(_operatorId, _tokenIds, totalNftRewards + totalCompensated);
    }

    /**
     * @notice The operator claims the operation reward
     * @param _operatorId operator Id
     * @param _reward operator reward
     */
    function claimRewardsOfOperator(uint256 _operatorId, uint256 _reward)
        external
        nonReentrant
        whenNotPaused
        onlyVaultManager
    {
        require(operatorLoanRecords[_operatorId] == 0, "The operator is in arrears");

        uint256 pledgeBalance = 0;
        uint256 requirBalance = 0;
        (pledgeBalance, requirBalance) = nodeOperatorRegistryContract.getPledgeInfoOfOperator(_operatorId);
        require(pledgeBalance >= requirBalance, "Insufficient pledge of operator");

        address[] memory rewardAddresses;
        uint256[] memory ratios;
        (rewardAddresses, ratios) = nodeOperatorRegistryContract.getNodeOperatorRewardSetting(_operatorId);
        require(rewardAddresses.length != 0, "Invalid rewardAddresses");
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);

        uint256 totalAmount = 0;
        uint256 totalRatios = 0;
        for (uint256 i = 0; i < rewardAddresses.length; ++i) {
            uint256 ratio = ratios[i];
            totalRatios += ratio;

            // If it is the last reward address, calculate by subtraction
            if (i == rewardAddresses.length - 1) {
                IELVault(vaultContractAddress).transfer(_reward - totalAmount, rewardAddresses[i]);
            } else {
                uint256 reward = _reward * ratio / 100;
                IELVault(vaultContractAddress).transfer(reward, rewardAddresses[i]);
                totalAmount += reward;
            }
        }

        require(totalRatios == 100, "Invalid ratio");

        emit OperatorClaimRewards(_operatorId, _reward);
    }

    /**
     * @notice The dao claims to belong to the dao reward
     * @param _operatorIds operators Id
     * @param _rewards rewards
     */
    function claimRewardsOfDao(uint256[] memory _operatorIds, uint256[] memory _rewards)
        external
        nonReentrant
        whenNotPaused
        onlyVaultManager
    {
        require(_operatorIds.length == _rewards.length && _rewards.length != 0, "parameter invalid length");
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 _operatorId = _operatorIds[i];
            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
            IELVault(vaultContractAddress).transfer(_rewards[i], daoVaultAddress);
            emit DaoClaimRewards(_operatorId, _rewards[i]);
        }
    }

    /**
     * @notice Get the total amount of ETH in the protocol
     */
    function getTotalEthValue() public view returns (uint256) {
        return
            operatorPoolBalancesSum + beaconOracleContract.getClBalances() + beaconOracleContract.getPendingBalances();
    }

    /**
     * @notice nETH to ETH exchange rate
     * @param _nethAmountIn nETH amount
     */
    function getEthOut(uint256 _nethAmountIn) public view returns (uint256) {
        uint256 totalEth = getTotalEthValue();
        uint256 nethSupply = nETHContract.totalSupply();
        if (nethSupply == 0) {
            return _nethAmountIn;
        }

        return _nethAmountIn * (totalEth) / (nethSupply);
    }

    /**
     * @notice ETH to nETH exchange rate
     * @param _ethAmountIn ETH amount
     */
    function getNethOut(uint256 _ethAmountIn) public view returns (uint256) {
        uint256 totalEth = getTotalEthValue();
        uint256 nethSupply = nETHContract.totalSupply();
        if (nethSupply == 0) {
            return _ethAmountIn;
        }
        require(totalEth > 0, "totalEth is zero");
        return _ethAmountIn * (nethSupply) / (totalEth);
    }

    /**
     * @notice nETH to ETH exchange rate
     */
    function getExchangeRate() external view returns (uint256) {
        return getEthOut(1 ether);
    }

    /**
     * @notice set dao address
     * @param _dao new dao address
     */
    function setDaoAddress(address _dao) external onlyOwner {
        require(_dao != address(0), "Dao address invalid");
        emit DaoAddressChanged(dao, _dao);
        dao = _dao;
    }

    /**
     * @notice set dao vault address
     * @param _daoVaultAddress new dao vault address
     */
    function setDaoVaultAddress(address _daoVaultAddress) external onlyDao {
        require(_daoVaultAddress != address(0), "dao vault address invalid");
        emit DaoVaultAddressChanged(daoVaultAddress, _daoVaultAddress);
        daoVaultAddress = _daoVaultAddress;
    }

    /**
     * @notice Set staking fee rate
     * @param _feeRate new stake fee rate
     */
    function setDepositFeeRate(uint256 _feeRate) external onlyDao {
        require(_feeRate <= 1000, "Rate too high");
        emit DepositFeeRateSet(depositFeeRate, _feeRate);
        depositFeeRate = _feeRate;
    }

    /**
     * @notice Set LiquidStaking contract withdrawalCredentials
     * @param _liquidStakingWithdrawalCredentials new withdrawalCredentials
     */
    function setLiquidStakingWithdrawalCredentials(bytes calldata _liquidStakingWithdrawalCredentials)
        external
        onlyOwner
    {
        emit LiquidStakingWithdrawalCredentialsSet(
            liquidStakingWithdrawalCredentials, _liquidStakingWithdrawalCredentials
            );
        liquidStakingWithdrawalCredentials = _liquidStakingWithdrawalCredentials;
    }

    /**
     * @notice Set new vaultManagerContractA address
     * @param _vaultManagerContract new vaultManagerContract address
     */
    function setVaultManagerContract(address _vaultManagerContract) external onlyDao {
        emit VaultManagerContractSet(vaultManagerContractAddress, _vaultManagerContract);
        vaultManagerContractAddress = _vaultManagerContract;
    }

    /**
     * @notice Set new consensusVaultContract address
     * @param _consensusVaultContract new consensusVaultContract address
     */
    function setConsensusVaultContract(address _consensusVaultContract) external onlyDao {
        emit ConsensusVaultContractSet(vaultManagerContractAddress, _consensusVaultContract);
        consensusVaultContract = IConsensusVault(_consensusVaultContract);
    }

    /**
     * @notice Set new beaconOracleContract address
     * @param _beaconOracleContractAddress new beaconOracleContract address
     */
    function setBeaconOracleContract(address _beaconOracleContractAddress) external onlyDao {
        emit BeaconOracleContractSet(address(beaconOracleContract), _beaconOracleContractAddress);
        beaconOracleContract = IWithdrawOracle(_beaconOracleContractAddress);
    }

    /**
     * @notice Set new nodeOperatorRegistryContract address
     * @param _nodeOperatorRegistryContract new withdrawalCredentials
     */
    function setNodeOperatorRegistryContract(address _nodeOperatorRegistryContract) external onlyDao {
        emit NodeOperatorRegistryContractSet(address(nodeOperatorRegistryContract), _nodeOperatorRegistryContract);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContract);
    }

    /**
     * @notice Set new operatorCanLoanAmounts
     * @param _newCanloadAmounts new _newCanloadAmounts
     */
    function setOperatorCanLoanAmounts(uint256 _newCanloadAmounts) public onlyDao {
        require(_newCanloadAmounts <= 1000 ether, "_newCanloadAmounts too large");
        emit OperatorCanLoanAmountsSet(operatorCanLoanAmounts, _newCanloadAmounts);
        operatorCanLoanAmounts = _newCanloadAmounts;
    }

    /**
     * @notice vNFT receiving function
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    /**
     * @notice Receive Rewards
     * @param _rewards rewards amount
     */
    function receiveRewards(uint256 _rewards) external payable {
        emit RewardsReceive(_rewards);
    }

    /**
     * @notice The protocol has been Paused
     */
    function isPaused() public view returns (bool) {
        return paused();
    }

    /**
     * @notice In the event of an emergency, stop protocol
     */
    function pause() external onlyDao {
        _pause();
    }

    /**
     * @notice restart protocol
     */
    function unpause() external onlyDao {
        _unpause();
    }
}
