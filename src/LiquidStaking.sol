// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "openzeppelin-contracts/utils/math/Math.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/INETH.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/IDepositContract.sol";
import "src/interfaces/IBeaconOracle.sol";
import "src/interfaces/IELVault.sol";
import {ERC721A__IERC721ReceiverUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";


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
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC721A__IERC721ReceiverUpgradeable
{
    using Math for uint256;

    IDepositContract public depositContract;

    INodeOperatorsRegistry public nodeOperatorRegistryContract;

    INETH public nETHContract;

    IVNFT public vNFTContract;

    IBeaconOracle public beaconOracleContract;

    bytes public liquidStakingWithdrawalCredentials;

    // deposit fee rate
    uint256 public depositFeeRate;
    uint256 public constant totalBasisPoints = 10000;

    uint256 public constant DEPOSIT_SIZE = 32 ether;

    // After the Shanghai upgrade, the rewards will be distributed linearly,
    // and the rewards will not exceed 16ETH, so the maximum value of a node is set to 48ETH
    uint256 public constant MAX_NODE_VALUE = 48 ether;

    // All validator tokenids in the liquidStaking pool
    uint256[] internal _liquidNfts;
    // All validator tokenids of the operator
    mapping(uint256 => uint256[]) internal _operatorNfts;
    // All validator tokenids belonging to the user
    mapping(uint256 => bool) internal _liquidUserNfts;

    // operator's internal stake pool, key is operator_id
    mapping(uint256 => uint256) public operatorPoolBalances;

    // Number of Wrap/Unwrap
    uint256 public nftWrapNonce;

    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;

    // unused funds in the current liquidStaking pool
    uint256 internal operatorPoolBalancesSum;

    // historical total Rewards
    uint256 public totalReinvestRewardsSum;

    modifier onlyDao() {
        require(msg.sender == dao, "PERMISSION_DENIED");
        _;
    }

    event OperatorRegister(string _name, address _controllerAddress, address _owner, uint256 operatorId);
    event OperatorWithdraw(uint256 operatorId, uint256 withdrawAmount, address to);
    event OperatorQuit(uint256 operatorId, uint256 substituteOperatorId, uint256 nowVault, address to);
    event BlacklistOperatorAssigned(uint256 blacklistOperatorId, uint256 totalAmount);
    event EthStake(address indexed from, uint256 amount, uint256 amountOut);
    event EthUnstake(address indexed from, uint256 amount, uint256 amountOut);
    event NftStake(address indexed from, uint256 count);
    event ValidatorRegistered(uint256 operator, uint256 tokenId);
    event NftWrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event NftUnwrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event UserClaimRewards(uint256 operatorId, uint256 rewards);
    event Transferred(address _to, uint256 _amount);
    event NFTMinted(uint256 tokenId);
    event OperatorReinvestRewards(uint256 operatorId, uint256 rewards);
    event OperatorClaimRewards(uint256 operatorId, uint256 rewards);
    event DaoClaimRewards(uint256 operatorId, uint256 rewards);
    event RewardsReceive(uint256 rewards);
    event SlashReceive(uint256 amount);
    event LiquidStakingWithdrawalCredentialsSet(
        bytes oldLiquidStakingWithdrawalCredentials, bytes _liquidStakingWithdrawalCredentials
    );
    event BeaconOracleContractSet(address oldBeaconOracleContract, address _beaconOracleContractAddress);
    event NodeOperatorRegistryContractSet(
        address oldNodeOperatorRegistryContract, address _nodeOperatorRegistryContract
    );

    /**
     * @notice initialize LiquidStaking Contract
     * @param _dao Dao contract address
     * @param _daoVaultAddress Dao Vault Address
     * @param withdrawalCreds Withdrawal Credentials, Withdrawal vault contract address
     * @param _nodeOperatorRegistryContractAddress Node Operator Registry Contract Address
     * @param _nETHContractAddress NETH contract address, The liquidity token for the eth stake
     * @param _nVNFTContractAddress VNFT contract address, The NFT representing the validator
     * @param _beaconOracleContractAddress Beacon Oracle Contract Address, where balances and VNFT values are tracked
     * @param _depositContractAddress eth2 Deposit Contract Address
     */
    function initialize(
        address _dao,
        address _daoVaultAddress,
        bytes memory withdrawalCreds,
        address _nodeOperatorRegistryContractAddress,
        address _nETHContractAddress,
        address _nVNFTContractAddress,
        address _beaconOracleContractAddress,
        address _depositContractAddress
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        dao = _dao;
        daoVaultAddress = _daoVaultAddress;

        liquidStakingWithdrawalCredentials = withdrawalCreds;

        depositContract = IDepositContract(_depositContractAddress);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContractAddress);

        nETHContract = INETH(_nETHContractAddress);

        vNFTContract = IVNFT(_nVNFTContractAddress);

        beaconOracleContract = IBeaconOracle(_beaconOracleContractAddress);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Register an operator to accept the user's stake
     * @param _name operator name
     * @param _controllerAddress operator contraller address
     * @param _owner This address is the operator owner and has the authority to change the control address and rewards address
     * @param _rewardAddresses Up to three addresses that accept operator rewards can be set
     * @param _ratios The allocation ratio corresponding to the rewards address by the operator
     */
    function registerOperator(
        string memory _name,
        address _controllerAddress,
        address _owner,
        address[] memory _rewardAddresses,
        uint256[] memory _ratios
    ) external payable whenNotPaused returns (uint256) {
        require(bytes(_name).length <= 32, "Invalid length");
        uint256 operatorId = nodeOperatorRegistryContract.registerOperator{value: msg.value}(
            _name, _controllerAddress, _owner, _rewardAddresses, _ratios
        );
        emit OperatorRegister(_name, _controllerAddress, _owner, operatorId);
    }

    /**
     * @notice Withdraw the deposit available to the operator, it must be sent by the operator owner
     * @param operatorId operator id
     * @param withdrawAmount withdrawal amount
     */
    function withdrawOperator(uint256 operatorId, uint256 withdrawAmount, address to) external whenNotPaused {
        address owner = nodeOperatorRegistryContract.getNodeOperatorOwner(operatorId);
        require(owner == msg.sender, "Permission denied");
        uint256 operatorNftCounts = vNFTContract.getNftCountsOfOperator(operatorId);
        uint256 requireVault = 0;
        if (operatorNftCounts <= 100) {
            requireVault = (operatorNftCounts * 10 / 100) * 1 ether;
        } else {
            requireVault = operatorNftCounts.sqrt() * 1 ether;
        }
        uint256 nowPledge = nodeOperatorRegistryContract.getPledgeBalanceOfOperator(operatorId);
        require(nowPledge >= requireVault + withdrawAmount, "Insufficient pledge balance");

        nodeOperatorRegistryContract.withdraw(withdrawAmount, operatorId, to);

        emit OperatorWithdraw(operatorId, withdrawAmount, to);
    }

    /**
     * @notice Exit the operator. When there are no validators running, the owner of the operator has the right to opt out.
     * Unused funds must be transferred to another active operator
     * @param operatorId operator id
     * @param substituteOperatorId An active operator that receives remaining available funds from exiting the operator
     * @param to The receiving address of the pledged funds of the withdrawn operator
     */
    function quitOperator(uint256 operatorId, uint256 substituteOperatorId, address to) external whenNotPaused {
        address owner = nodeOperatorRegistryContract.getNodeOperatorOwner(operatorId);
        require(owner == msg.sender, "Permission denied");
        uint256 operatorNftCounts = vNFTContract.getNftCountsOfOperator(operatorId);
        require(operatorNftCounts == 0, "unable to exit");

        // substituteOperatorId must be a trusted operator
        require(
            nodeOperatorRegistryContract.isTrustedOperator(substituteOperatorId),
            "The substituteOperatorId is not trusted"
        );

        uint256 balance = operatorPoolBalances[operatorId];
        operatorPoolBalances[operatorId] = 0;
        operatorPoolBalances[substituteOperatorId] += balance;

        uint256 nowPledge = nodeOperatorRegistryContract.getPledgeBalanceOfOperator(operatorId);
        nodeOperatorRegistryContract.withdraw(nowPledge, operatorId, to);
        emit OperatorQuit(operatorId, substituteOperatorId, nowPledge, to);
    }

    /**
     * @notice For operators added to the blacklist by dao, for example, because the operator has been inactive for a long time, and has been punished on a large scale, etc.
     * The Dao has the right to distribute the available balance on this operator to other active operators,
     * and the allocation share will be determined through proposals
     * @param blacklistOperatorId blacklist operator id
     * @param operatorIds The operator id of the allocation share
     * @param amounts The size of the allocated share
     */
    function assignBlacklistOperator(
        uint256 blacklistOperatorId,
        uint256[] memory operatorIds,
        uint256[] memory amounts
    ) public onlyDao whenNotPaused {
        // blacklistOperatorId must be a blacklist operator
        require(
            !nodeOperatorRegistryContract.isTrustedOperator(blacklistOperatorId),
            "This operator is not in the blacklist"
        );
        require(operatorIds.length == amounts.length, "Invalid length");
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < operatorIds.length; i++) {
            uint256 operatorId = operatorIds[i];
            uint256 amount = amounts[i];
            totalAmount += amount;
            operatorPoolBalances[operatorId] += amount;
        }

        require(operatorPoolBalances[blacklistOperatorId] >= totalAmount, "Insufficient balance of blacklist operator");
        operatorPoolBalances[blacklistOperatorId] -= totalAmount;
        emit BlacklistOperatorAssigned(blacklistOperatorId, totalAmount);
    }

    /**
     * @notice stake eth to designated operator, stake ETH to get nETH
     * @param _operatorId operator id
     */
    function stakeETH(uint256 _operatorId) external payable nonReentrant whenNotPaused {
        require(msg.value >= 1000 wei, "Stake amount must be minimum  1000 wei");

        // operatorId must be a trusted operator
        require(nodeOperatorRegistryContract.isTrustedOperator(_operatorId), "The operator is not trusted");
        require(nodeOperatorRegistryContract.isConformBasicPledge(_operatorId), "Insufficient pledge balance");

        uint256 depositFeeAmount;
        uint256 depositPoolAmount;
        if (depositFeeRate == 0) {
            depositPoolAmount = msg.value;
        } else {
            depositFeeAmount = msg.value * depositFeeRate / totalBasisPoints;
            depositPoolAmount = msg.value - depositFeeAmount;
            transfer(depositFeeAmount, daoVaultAddress);
        }

        // 1. Convert depositAmount according to the exchange rate of nETH
        // 2. Mint nETH
        uint256 amountOut = getNethOut(depositPoolAmount);
        nETHContract.whiteListMint(amountOut, msg.sender);

        operatorPoolBalances[_operatorId] += depositPoolAmount;
        operatorPoolBalancesSum += depositPoolAmount;

        emit EthStake(msg.sender, msg.value, amountOut);
    }

    function transfer(uint256 amount, address to) internal {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }

    /**
     * @notice unstakeETH Support after Shanghai upgrade
     * @param amount unstake nETH amount
     */
    function unstakeETH(uint256 amount) external nonReentrant {
        require(false, "Not supported yet");
    }

    /**
     * @notice unstakeNFT Support after Shanghai upgrade
     * @param data unstakeNFT data
     */
    function unstakeNFT(bytes[] calldata data) public nonReentrant whenNotPaused returns (bool) {
        return data.length == 0;
    }

    /**
     * @notice Stake 32 multiples of eth to get the corresponding number of vNFTs
     * @param _operatorId operator id
     */
    function stakeNFT(uint256 _operatorId) external payable nonReentrant whenNotPaused {
        // operatorId must be a trusted operator
        require(nodeOperatorRegistryContract.isTrustedOperator(_operatorId), "The operator is not trusted");
        require(msg.value % DEPOSIT_SIZE == 0, "Incorrect Ether amount provided");

        require(nodeOperatorRegistryContract.isConformBasicPledge(_operatorId), "Insufficient pledge balance");

        uint256 amountOut = getNethOut(msg.value);

        _settle(_operatorId);

        nETHContract.whiteListMint(amountOut, address(this));

        uint256 mintNftsCount = msg.value / DEPOSIT_SIZE;
        for (uint256 i = 0; i < mintNftsCount; i++) {
            uint256 tokenId;
            (, tokenId) = vNFTContract.whiteListMint(bytes(""), msg.sender, _operatorId);
            emit NFTMinted(tokenId);
            _liquidNfts.push(tokenId);
            _operatorNfts[_operatorId].push(tokenId);
            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
            IELVault(vaultContractAddress).setUserNft(tokenId, block.number);
        }

        operatorPoolBalances[_operatorId] += msg.value;
        operatorPoolBalancesSum += msg.value;

        emit NftStake(msg.sender, mintNftsCount);
    }

    /**
     * @notice registers validators
     * @param pubkeys validator pubkeys
     * @param signatures validator signatures
     * @param depositDataRoots validator depositDataRoots
     */
    function registerValidator(
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) external nonReentrant whenNotPaused {
        require(
            pubkeys.length == signatures.length && pubkeys.length == depositDataRoots.length,
            "All parameter array's must have the same length."
        );

        // must be a trusted operator
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        require(operatorId != 0, "msg.sender must be the controllerAddress of the trusted operator");
        require(operatorPoolBalances[operatorId] / DEPOSIT_SIZE >= pubkeys.length, "Insufficient balance");

        _settle(operatorId);

        for (uint256 i = 0; i < pubkeys.length; i++) {
            _stakeAndMint(operatorId, pubkeys[i], signatures[i], depositDataRoots[i]);
        }

        uint256 stakeAmount = DEPOSIT_SIZE * pubkeys.length;
        operatorPoolBalances[operatorId] -= stakeAmount;
        operatorPoolBalancesSum -= stakeAmount;
        beaconOracleContract.addPendingBalances(stakeAmount);
    }

    function _settle(uint256 operatorId) internal {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();
    }

    function _stakeAndMint(uint256 operatorId, bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot)
        internal
    {
        depositContract.deposit{value: 32 ether}(pubkey, liquidStakingWithdrawalCredentials, signature, depositDataRoot);

        // mint nft
        bool isMint;
        uint256 tokenId;
        (isMint, tokenId) = vNFTContract.whiteListMint(pubkey, address(this), operatorId);
        if (isMint) {
            _liquidNfts.push(tokenId);
            _operatorNfts[operatorId].push(tokenId);
        }

        emit ValidatorRegistered(operatorId, tokenId);
    }

    /**
     * @notice nETH swap vNFT
     * @param tokenId vNFT tokenId
     * @param proof Merkle tree proof from the oracle for this validator
     * @param value value from the oracle for this validator
     */
    function wrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant whenNotPaused {
        require(value >= DEPOSIT_SIZE, "Value check failed");

        uint256 operatorId = vNFTContract.operatorOf(tokenId);

        reinvestRewardsOfOperator(operatorId);

        uint256 amountOut = getNethOut(value);

        bytes memory pubkey = vNFTContract.validatorOf(tokenId);
        bool success = beaconOracleContract.verifyNftValue(proof, pubkey, value, tokenId);
        require(success, "verifyNftValue fail");

        // this might need to use transfer instead
        success = nETHContract.transferFrom(msg.sender, address(this), amountOut);
        require(success, "Failed to transfer neth");

        vNFTContract.safeTransferFrom(address(this), msg.sender, tokenId);

        _liquidUserNfts[tokenId] = true;

        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).setUserNft(tokenId, block.number);
        nftWrapNonce = nftWrapNonce + 1;

        emit NftWrap(tokenId, operatorId, value, amountOut);
    }

    /**
     * @notice vNFT swap nETH
     * @param tokenId vNFT tokenId
     * @param proof Merkle tree proof from the oracle for this validator
     * @param value value from the oracle for this validator
     */
    function unwrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant whenNotPaused {
        require(value <= MAX_NODE_VALUE, "Value check failed");

        uint256 operatorId = vNFTContract.operatorOf(tokenId);

        bool trusted;
        address vaultContractAddress;
        (trusted,,,, vaultContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        require(trusted, "permission denied");

        bytes memory pubkey = vNFTContract.validatorOf(tokenId);
        bool success = beaconOracleContract.verifyNftValue(proof, pubkey, value, tokenId);
        require(success, "verifyNftValue fail");

        uint256 amountOut = getNethOut(value);

        _liquidUserNfts[tokenId] = false;

        claimRewardsOfUser(tokenId);
        vNFTContract.safeTransferFrom(msg.sender, address(this), tokenId);
        // success = nETHContract.transferFrom(address(this), msg.sender, amountOut);
        success = nETHContract.transfer(msg.sender, amountOut);
        require(success, "Failed to transfer neth");

        IELVault(vaultContractAddress).setUserNft(tokenId, 0);
        nftWrapNonce = nftWrapNonce + 1;

        emit NftUnwrap(tokenId, operatorId, value, amountOut);
    }

    /**
     * @notice How much nETH can be obtained by trading vNFT
     * @param tokenId vNFT tokenId
     * @param proof Merkle tree proof from the oracle for this validator
     * @param value value from the oracle for this validator
     */
    function getNFTOut(uint256 tokenId, bytes32[] memory proof, uint256 value) external view returns (uint256) {
        uint256 operatorId = vNFTContract.operatorOf(tokenId);

        bool trusted;
        address vaultContractAddress;
        (trusted,,,, vaultContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        require(trusted, "permission denied");

        bytes memory pubkey = vNFTContract.validatorOf(tokenId);
        bool success = beaconOracleContract.verifyNftValue(proof, pubkey, value, tokenId);
        require(success, "verifyNftValue fail");

        return getNethOut(value);
    }

    /**
     * @notice Batch Reinvestment Rewards
     * @param operatorIds The operatorIds of the re-investment
     */
    function batchReinvestRewardsOfOperator(uint256[] memory operatorIds) public whenNotPaused {
        for (uint256 i = 0; i < operatorIds.length; i++) {
            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorIds[i]);
            IELVault(vaultContractAddress).settle();

            uint256 nftRewards = IELVault(vaultContractAddress).reinvestmentOfLiquidStaking();
            IELVault(vaultContractAddress).setLiquidStakingGasHeight(block.number);

            operatorPoolBalances[operatorIds[i]] += nftRewards;
            operatorPoolBalancesSum += nftRewards;
            emit OperatorReinvestRewards(operatorIds[i], nftRewards);
        }
    }

    /**
     * @notice Reinvestment Rewards
     * @param operatorId The operatorId of the re-investment
     */
    function reinvestRewardsOfOperator(uint256 operatorId) public whenNotPaused {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();

        uint256 nftRewards = IELVault(vaultContractAddress).reinvestmentOfLiquidStaking();
        IELVault(vaultContractAddress).setLiquidStakingGasHeight(block.number);

        operatorPoolBalances[operatorId] += nftRewards;
        operatorPoolBalancesSum += nftRewards;
        emit OperatorReinvestRewards(operatorId, nftRewards);
    }

    /**
     * @notice Users claim vNFT rewards
     * @param tokenId vNFT tokenId
     */
    function claimRewardsOfUser(uint256 tokenId) public whenNotPaused {
        uint256 operatorId = vNFTContract.operatorOf(tokenId);
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();

        uint256 nftRewards = IELVault(vaultContractAddress).claimRewardsOfUser(tokenId);

        emit UserClaimRewards(operatorId, nftRewards);
    }

    /**
     * @notice The operator claims the operation reward
     * @param operatorId operator Id
     */
    function claimRewardsOfOperator(uint256 operatorId) public whenNotPaused {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();
        uint256 operatorRewards = IELVault(vaultContractAddress).claimOperatorRewards();

        emit OperatorClaimRewards(operatorId, operatorRewards);
    }

    /**
     * @notice The dao claims to belong to the dao reward
     * @param operatorId operator Id
     */
    function claimRewardsOfDao(uint256 operatorId) public whenNotPaused {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);

        IELVault(vaultContractAddress).settle();
        uint256 daoRewards = IELVault(vaultContractAddress).claimDaoRewards(daoVaultAddress);

        emit DaoClaimRewards(operatorId, daoRewards);
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
        require(totalEth > 0, "Cannot calculate nETH token amount while balance is zero");
        return _ethAmountIn * (nethSupply) / (totalEth);
    }

    /**
     * @notice nETH to ETH exchange rate
     */
    function getExchangeRate() external view returns (uint256) {
        return getEthOut(1 ether);
    }

    /**
     * @notice The total number of validators currently owned by the stake pool
     */
    function getLiquidValidatorsCount() public view returns (uint256) {
        return getLiquidNfts().length;
    }

    /**
     * @notice Validators currently owned by the stake pool
     */
    function getLiquidNfts() public view returns (uint256[] memory) {
        uint256 nftCount = 0;
        uint256[] memory liquidNfts;
        uint256 i = 0;
        for (i = 0; i < _liquidNfts.length; i++) {
            uint256 tokenId = _liquidNfts[i];
            if (!_liquidUserNfts[tokenId]) {
                nftCount += 1;
            }
        }

        liquidNfts = new uint256[] (nftCount);
        uint256 j = 0;
        for (i = 0; i < _liquidNfts.length; i++) {
            uint256 tokenId = _liquidNfts[i];
            if (!_liquidUserNfts[tokenId]) {
                liquidNfts[j] = tokenId;
                j += 1;
            }
        }

        return liquidNfts;
    }

    /**
     * @notice Validators currently owned by the user
     */
    function getUserNfts() public view returns (uint256[] memory) {
        uint256 nftCount = 0;
        uint256[] memory userNfts;
        uint256 i = 0;
        for (i = 0; i < _liquidNfts.length; i++) {
            uint256 tokenId = _liquidNfts[i];
            if (_liquidUserNfts[tokenId]) {
                nftCount += 1;
            }
        }

        userNfts = new uint256[] (nftCount);
        uint256 j = 0;
        for (i = 0; i < _liquidNfts.length; i++) {
            uint256 tokenId = _liquidNfts[i];
            if (_liquidUserNfts[tokenId]) {
                userNfts[j] = tokenId;
                j += 1;
            }
        }

        return userNfts;
    }

    /**
     * @notice Validators that belongs to the operator
     * @param operatorId operator Id
     */
    function getOperatorNfts(uint256 operatorId) public view returns (uint256[] memory) {
        uint256 nftCount = 0;
        uint256[] memory operatorNfts;

        uint256[] memory nfts = _operatorNfts[operatorId];
        uint256 i = 0;
        for (i = 0; i < nfts.length; i++) {
            uint256 tokenId = nfts[i];
            if (!_liquidUserNfts[tokenId]) {
                nftCount += 1;
            }
        }

        operatorNfts = new uint256[] (nftCount);
        uint256 j = 0;
        for (i = 0; i < nfts.length; i++) {
            uint256 tokenId = nfts[i];
            if (!_liquidUserNfts[tokenId]) {
                operatorNfts[j] = tokenId;
                j += 1;
            }
        }

        return operatorNfts;
    }

    /**
     * @notice set dao address
     * @param _dao new dao address
     */
    function setDaoAddress(address _dao) external onlyDao {
        dao = _dao;
    }

    /**
     * @notice Set staking fee rate
     * @param _feeRate new stake fee rate
     */
    function setDepositFeeRate(uint256 _feeRate) external onlyDao {
        require(_feeRate <= 1000, "Rate too high");
        depositFeeRate = _feeRate;
    }

    /**
     * @notice Set LiquidStaking contract withdrawalCredentials
     * @param _liquidStakingWithdrawalCredentials new withdrawalCredentials
     */
    function setLiquidStakingWithdrawalCredentials(bytes memory _liquidStakingWithdrawalCredentials) external onlyDao {
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
     * @param rewards rewards amount
     */
    function receiveRewards(uint256 rewards) external payable {
        totalReinvestRewardsSum += rewards;
        emit RewardsReceive(rewards);
    }

    /**
     * @notice Receive slash fund
     * @param amount amount
     */
    function slashReceive(uint256 amount) external payable {
        emit SlashReceive(amount);
    }

    /**
     * @notice The protocol has been Paused
     */
    function isPaused() public view returns (bool) {
        paused();
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
