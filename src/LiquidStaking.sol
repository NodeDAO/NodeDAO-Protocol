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
import "src/interfaces/IBeaconOracle.sol";
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

    IBeaconOracle public beaconOracleContract;

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

    struct StakeInfo {
        uint256 operatorId;
        uint256 quota;
    }

    // key is user address, value is
    mapping(address => StakeInfo[]) public stakeRecords;
    // key is quit operatorId, value is asign operatorId
    mapping(uint256 => uint256) public reAssignRecords;
    // key is operatorId, value is loan amounts
    mapping(uint256 => uint256) public operatorLoanRecords;
    // key is operatorId, value is loan blockNumber
    mapping(uint256 => uint256) public operatorLoadBlockNumbers;
    // key is tokenId, value is nft unstake blocknumber
    mapping(uint256 => uint256) public nftUnstakeBlockNumbers;
    // key is operatorId, value is operatorUnstakeNftLists
    mapping(uint256 => uint256[]) internal operatorUnstakeNftLists;
    // key is tokenId, value is nft compensated
    mapping(uint256 => uint256) public nftWillCompensated;
    mapping(uint256 => uint256) public nftHasCompensated;
    mapping(uint256 => uint256[]) public operatorSlashArrears;
    uint256 public operatorCompensatedIndex;

    function getOperatorWillExitNfsList(uint256 _operatorId) external view returns (uint256[] memory) {
        // operatorUnstakeNftLists & userNftExitBlockNumbers != 0
    }

    function getOperatorLoadBlockNumber(uint256 _operatorId) external view returns (uint256) {
        return operatorLoadBlockNumbers[_operatorId];
    }

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

        beaconOracleContract = IBeaconOracle(_beaconOracleContractAddress);
    }

    function initializeV2() public reinitializer(2) onlyDao {
        // merge already stake data to StakeRecords
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice For operators added to the blacklist by dao, for example,
     * because the operator has been inactive for a long time,
     * and has been punished on a large scale, etc.
     *
     * The Dao has the right to distribute the available balance on this operator to other active operators,
     * and the allocation share will be determined through proposals
     * @param _assignOperatorId blacklist or quit operator id
     * @param _operatorIds The operator id of the allocation share
     * @param _amounts The size of the allocated share
     */
    function assignBlacklistOrQuitOperator(
        uint256 _assignOperatorId,
        uint256[] calldata _operatorIds,
        uint256[] calldata _amounts
    ) external onlyOwner {
        // assignOperatorId must be a blacklist operator
        require(
            !nodeOperatorRegistryContract.isTrustedOperator(_assignOperatorId)
                || nodeOperatorRegistryContract.isQuitOperator(_assignOperatorId),
            "This operator is trusted"
        );
        require(_operatorIds.length == _amounts.length, "Invalid length");

        // Update operator available funds
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _operatorIds.length; ++i) {
            uint256 operatorId = _operatorIds[i];
            require(nodeOperatorRegistryContract.isTrustedOperator(operatorId), "Operator must be trusted");
            uint256 amount = _amounts[i];
            totalAmount += amount;
            operatorPoolBalances[operatorId] += amount;
        }

        require(operatorPoolBalances[_assignOperatorId] >= totalAmount, "Insufficient balance of blacklist operator");
        operatorPoolBalances[_assignOperatorId] -= totalAmount;
        emit BlacklistOperatorAssigned(_assignOperatorId, totalAmount);
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

        emit EthStake(msg.sender, msg.value, amountOut);
    }

    function _updateStakeFundLedger(uint256 _operatorId, uint256 _amount) internal {
        uint256 loanAmounts = operatorLoanRecords[_operatorId];
        if (loanAmounts > 0) {
            if (loanAmounts > _amount) {
                operatorLoanRecords[_operatorId] -= _amount;
            } else {
                operatorLoanRecords[_operatorId] = 0;
                operatorLoadBlockNumbers[_operatorId] = 0;
                operatorPoolBalances[_operatorId] += (_amount - loanAmounts);
            }
        }

        operatorPoolBalancesSum += _amount;
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

        uint256 loanAmounts = operatorLoanRecords[_operatorId];
        if (loanAmounts > 0) {
            operatorLoanRecords[_operatorId] = 0;
            operatorLoadBlockNumbers[_operatorId] = 0;
            operatorPoolBalances[_operatorId] += (msg.value - loanAmounts);
        } else {
            operatorPoolBalances[_operatorId] += msg.value;
        }

        operatorPoolBalancesSum += msg.value;

        emit NftStake(msg.sender, mintNftsCount);
    }

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
                _updateUnstakeFundLedger(DEPOSIT_SIZE, operatorId);
                payable(msg.sender).transfer(DEPOSIT_SIZE);
                emit Transferred(msg.sender, DEPOSIT_SIZE);
                vNFTContract.whiteListBurn(tokenId);
            } else {
                nftUnstakeBlockNumbers[tokenId] = block.number;
                operatorUnstakeNftLists[operatorId].push(tokenId);
            }

            emit NftUnstake(tokenId, operatorId);
        }
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
            uint256 operatorCanLoanAmounts = operatorPoolBalancesSum * 5 / 100;
            require(
                (operatorCanLoanAmounts > operatorLoanAmounts + newLoanAmounts)
                    && operatorLoanAmounts + newLoanAmounts <= 32 ether,
                "Insufficient funds to unstake"
            );
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
        require(operatorPoolBalances[operatorId] / DEPOSIT_SIZE >= _pubkeys.length, "Insufficient balance");

        for (uint256 i = 0; i < _pubkeys.length; ++i) {
            _stakeAndMint(operatorId, _pubkeys[i], _signatures[i], _depositDataRoots[i]);
        }

        uint256 stakeAmount = DEPOSIT_SIZE * _pubkeys.length;
        operatorPoolBalances[operatorId] -= stakeAmount;
        operatorPoolBalancesSum -= stakeAmount;
        beaconOracleContract.addPendingBalances(stakeAmount);
    }

    function _stakeAndMint(
        uint256 _operatorId,
        bytes calldata _pubkey,
        bytes calldata _signature,
        bytes32 _depositDataRoot
    ) internal {
        bytes memory nextValidatorWithdrawalCredential = vNFTContract.getNextValidatorWithdrawalCredential(_operatorId);
        bytes memory _withdrawalCredential = (nextValidatorWithdrawalCredential.length != 0)
            ? nextValidatorWithdrawalCredential
            : liquidStakingWithdrawalCredentials;

        depositContract.deposit{value: 32 ether}(_pubkey, _withdrawalCredential, _signature, _depositDataRoot);

        uint256 tokenId = vNFTContract.whiteListMint(_pubkey, _withdrawalCredential, address(this), _operatorId);

        emit ValidatorRegistered(_operatorId, tokenId);
    }

    function nftExitHandle(uint256[] memory tokenIds, uint256[] memory exitBlockNumbers) external onlyVaultManager {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (vNFTContract.ownerOf(tokenId) == address(this)) {
                vNFTContract.whiteListBurn(tokenId);
            }
        }

        vNFTContract.setNftExitBlockNumbers(tokenIds, exitBlockNumbers);
        emit NftExitBlockNumberSet(tokenIds, exitBlockNumbers);
    }

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
            _updateStakeFundLedger(operatorId, _amount);
            emit OperatorReinvestClRewards(operatorId, _amount);
        }

        consensusVaultContract.reinvestment(totalReinvestRewards);
    }

    function slashOperator(uint256[] memory _exitTokenIds, uint256[] memory _amounts) external onlyVaultManager {
        require(_exitTokenIds.length == _amounts.length && _amounts.length != 0, "parameter invalid length");
        nodeOperatorRegistryContract.slash(_exitTokenIds, _amounts);
    }

    function slashReceive(
        uint256[] memory _exitTokenIds,
        uint256[] memory _slashAmount,
        uint256[] memory _requirAmounts
    ) external payable {
        require(msg.sender == address(nodeOperatorRegistryContract), "PERMISSION_DENIED");
        for (uint256 i = 0; i < _exitTokenIds.length; ++i) {
            uint256 tokenId = _exitTokenIds[i];
            uint256 operatorId = vNFTContract.operatorOf(tokenId);
            if (vNFTContract.ownerOf(tokenId) == address(this)) {
                _updateStakeFundLedger(operatorId, _slashAmount[i]);
            } else {
                uint256 requirAmount = _requirAmounts[i];
                uint256 slashAmount = _slashAmount[i];
                require(requirAmount >= slashAmount, "Abnormal slash amount");
                if (requirAmount != slashAmount) {
                    nftWillCompensated[tokenId] += requirAmount - slashAmount;
                    operatorSlashArrears[operatorId].push(tokenId);
                }
                nftHasCompensated[tokenId] += slashAmount;
            }

            emit SlashReceive(operatorId, tokenId, _slashAmount[i], _requirAmounts[i]);
        }
    }

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

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            require(owner == vNFTContract.ownerOf(tokenId), "different owners cannot batch");
            totalNftRewards += _amounts[i];

            if (exitBlockNumbers[i] != 0) {
                vNFTContract.whiteListBurn(tokenId);
            } else {
                vNFTContract.setUserNftGasHeight(tokenId, _gasHeight);
            }
        }

        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
        IELVault(vaultContractAddress).transfer(totalNftRewards, owner);

        emit UserClaimRewards(_operatorId, _tokenIds, totalNftRewards);
    }

    function claimRewardsOfOperator(uint256 _operatorId, uint256 _reward)
        external
        nonReentrant
        whenNotPaused
        onlyVaultManager
    {
        require(operatorLoanRecords[_operatorId] == 0, "The operator is in arrears");

        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
        uint256 pledgeBalance = 0;
        uint256 requirBalance = 0;
        (pledgeBalance, requirBalance) = nodeOperatorRegistryContract.getPledgeBalanceOfOperator(_operatorId);
        require(pledgeBalance >= requirBalance, "Insufficient pledge of operator");

        address[] memory rewardAddresses;
        uint256[] memory ratios;
        (rewardAddresses, ratios) = nodeOperatorRegistryContract.getNodeOperatorRewardSetting(_operatorId);
        require(rewardAddresses.length != 0, "Invalid rewardAddresses");

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
        return operatorPoolBalancesSum + beaconOracleContract.getBeaconBalances()
            + beaconOracleContract.getPendingBalances();
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
     * @notice Set new beaconOracleContract address
     * @param _beaconOracleContractAddress new withdrawalCredentials
     */
    function setBeaconOracleContract(address _beaconOracleContractAddress) external onlyDao {
        emit BeaconOracleContractSet(address(beaconOracleContract), _beaconOracleContractAddress);
        beaconOracleContract = IBeaconOracle(_beaconOracleContractAddress);
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
