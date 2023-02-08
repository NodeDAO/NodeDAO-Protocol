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

/*
    @title LiquidStaking Contract
    @author RenShiWei
    @notice Holds various methods relevant to staking
    @dev this contract inherits from Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable, ERC721A__IERC721ReceiverUpgradeable*/
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

    uint256 public depositFeeRate; // deposit fee rate
    uint256 public unstakeFeeRate; // unstake fee rate
    uint256 public constant totalBasisPoints = 10000;

    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 public constant MAX_NODE_VALUE = 48 ether;

    uint256[] internal _liquidNfts; // The validator tokenid owned by the stake pool
    mapping(uint256 => uint256[]) internal _operatorNfts;
    mapping(uint256 => bool) internal _liquidUserNfts; // The nft purchased from the staking pool using neth

    mapping(uint256 => uint256) public operatorPoolBalances; // operator's internal stake pool, key is operator_id

    uint256 public nftWrapNonce;

    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;

    uint256 internal operatorPoolBalancesSum;
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

    /*
        @title initialize LiquidStaking Contract
        @author llifezou
        @notice creates the liquidstaking contract
        @dev an external method with an initializer condition
        @param _dao Dao contract address 
        @param _daoVaultAddress Dao Vault Address
        @param withdrawalCreds Withdrawal Credentials
        @param _nodeOperatorRegistryContractAddress Node Operator Registry Contract Address, where operator methods can be called such as trusted checks and vault address look up.
        @param _nETHContractAddress NETH contract address, The liquidity token in exchange for the eth stake
        @param _nVNFTContractAddress VNFT contract address, The NFT representing a 1:1 stake (32 eth)
        @param _beaconOracleContractAddress Beacon Oracle Contract Address, where balances and VNFT values are tracked
        @param _depositContractAddress Deposit Contract Address, the contract where deposits are kept
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

        unstakeFeeRate = 5;
    }

    /*
        @title _authorizeUpgrade
        @author jefferson
        @notice ???
    */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function registerOperator(
        string memory _name,
        address _controllerAddress,
        address _owner,
        address[] memory _rewardAddresses,
        uint256[] memory _ratios
    ) external payable returns (uint256) {
        require(bytes(_name).length <= 32, "Invalid length"); // todo
        uint256 operatorId = nodeOperatorRegistryContract.registerOperator{value: msg.value}(
            _name, _controllerAddress, _owner, _rewardAddresses, _ratios
        );
        emit OperatorRegister(_name, _controllerAddress, _owner, operatorId);
    }

    function withdrawOperator(uint256 operatorId, uint256 withdrawAmount, address to) external {
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

    function quitOperator(uint256 operatorId, uint256 substituteOperatorId, address to) external {
        address owner = nodeOperatorRegistryContract.getNodeOperatorOwner(operatorId);
        require(owner == msg.sender, "Permission denied");
        uint256 operatorNftCounts = vNFTContract.getNftCountsOfOperator(operatorId);
        require(operatorNftCounts == 0, "unable to exit");

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

    function assignBlacklistOperator(
        uint256 blacklistOperatorId,
        uint256[] memory operatorIds,
        uint256[] memory amounts
    ) public onlyDao {
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

    /*
        @title stakeETH
        @author llifezou
        @notice stakes eth to designated operator
        @dev an external and payable method with an nonReentrant and whenNotPaused condition
        @param _operatorId Operator to stake with, has to be trusted
    */
    function stakeETH(uint256 _operatorId) external payable nonReentrant whenNotPaused {
        require(msg.value >= 1000 wei, "Stake amount must be minimum  1000 wei");
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

    /*
        @title unstakeETH
        @author llifezou
        @notice unstakes neth to eth, incomplete
        @dev an external method with nonReentrant condition
        @param amount Amount of neth
    */
    function unstakeETH(uint256 amount) external nonReentrant {
        require(false, "Not supported yet");
    }

    //1. depost
    //2. _operatorId must be a trusted operator
    /*
        @title stakeNFT
        @author llifezou
        @notice stakes NFT to designated operator
        @dev an external and payable method with an nonReentrant and whenNotPaused condition. msg.value must be in multiples of DEPOSIT SIZE (currently 32 eth). This will mint both NETH and VNFT and then STAKE NFT.
        @param _operatorId Operator to stake with, has to be trusted
    */
    function stakeNFT(uint256 _operatorId) external payable nonReentrant whenNotPaused {
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

    //1. Check whether msg.sender is the controllerAddress of the operator
    //2. Check if operator_id is trusted
    //3. precheck, need to add check withdrawalCredentials must be set by the stake pool
    //4. signercheck
    //5. depost
    //6. operatorPoolBalances[_operatorId] = operatorPoolBalances[_operatorId] -depositAmount;
    //7. mint nft, minting nft, stored in the stake pool contract, can no longer mint neth, because minting has been completed when the user deposits
    //8. Update _liquidNfts
    /*
        @title registerValidator
        @author llifezou
        @notice registers a validator
        @dev an external and payable method with an nonReentrant and whenNotPaused condition. msg.value must be in multiples of DEPOSIT SIZE (currently 32 eth). This will mint both NETH and VNFT and then STAKE NFT.
        @param pubkeys array of pubkeys that wants to stake and mint VNFT
        @param signatures array of signatures corresponding to the pubkeys
        @param depositDataRoots array of deposit data roots corresponding to the signatures <<
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

        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperatorOfControllerAddress(msg.sender);
        require(operatorId != 0, "msg.sender must be the controllerAddress of the trusted operator");
        require(getOperatorPoolEtherMultiple(operatorId) >= pubkeys.length, "Insufficient balance");

        _settle(operatorId);

        for (uint256 i = 0; i < pubkeys.length; i++) {
            _stakeAndMint(operatorId, pubkeys[i], signatures[i], depositDataRoots[i]);
        }

        uint256 stakeAmount = DEPOSIT_SIZE * pubkeys.length;
        operatorPoolBalances[operatorId] -= stakeAmount;
        operatorPoolBalancesSum -= stakeAmount;
        beaconOracleContract.addPendingBalances(stakeAmount);
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

    /*
        @title unstakeNFT
        @author llifezou
        @notice incomplete
        @param data array of calldata
    */
    function unstakeNFT(bytes[] calldata data) public nonReentrant whenNotPaused returns (bool) {
        return data.length == 0;
    }

    //wrap neth to nft
    //1. Check if the value matches the oracle
    //2. Check if the neth balance is satisfied -not required
    //3. Transfer user neth to the stake pool
    //4. Trigger the operator's claim once, and transfer the nft to the user
    //5. Record _liquidUserNfts as true
    //6. Set the vault contract setUserNft to block.number
    /*
        @title wrapNFT
        @author llifezou
        @notice transfers msg.sender's NETH to liquidstaking and transfer VNFT to msg.sender
        @dev an external method with an nonReentrant and whenNotPaused condition.
        @param tokenId 
        @param proof array of proofs
        @param value value of transaction to be verified
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

    //unwrap nft to neth
    //1. Check if the originator holds a token_id -not required
    //2. Check if the value matches the oracle
    //3. Claim income for the user, and transfer the user's nft to the stake pool
    //4. Transfer neth to the user
    //5. Set the vault contract setUserNft to 0
    /*
        @title unwrapNFT
        @author llifezou
        @notice transfers VNFT from msg.sender to liquidstaking contract and transfers NETH to msg.sender
        @dev an external method with an nonReentrant and whenNotPaused condition.
        @param tokenId 
        @param proof array of proofs
        @param value value of transaction to be verified
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

    //1. claim income operatorPoolBalances
    //2. Earnings are settled setLiquidStakingGasHeight
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

    //1. claim income operatorPoolBalances
    //2. Earnings are settled setLiquidStakingGasHeight
    function reinvestRewardsOfOperator(uint256 operatorId) public whenNotPaused {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();

        uint256 nftRewards = IELVault(vaultContractAddress).reinvestmentOfLiquidStaking();
        IELVault(vaultContractAddress).setLiquidStakingGasHeight(block.number);

        operatorPoolBalances[operatorId] += nftRewards;
        operatorPoolBalancesSum += nftRewards;
        emit OperatorReinvestRewards(operatorId, nftRewards);
    }

    function claimRewardsOfUser(uint256 tokenId) public whenNotPaused {
        uint256 operatorId = vNFTContract.operatorOf(tokenId);
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();

        uint256 nftRewards = IELVault(vaultContractAddress).claimRewardsOfUser(tokenId);

        emit UserClaimRewards(operatorId, nftRewards);
    }

    function claimRewardsOfOperator(uint256 operatorId) public whenNotPaused {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();
        uint256 operatorRewards = IELVault(vaultContractAddress).claimOperatorRewards();

        emit OperatorClaimRewards(operatorId, operatorRewards);
    }

    function claimRewardsOfDao(uint256 operatorId) public whenNotPaused {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);

        IELVault(vaultContractAddress).settle();
        uint256 daoRewards = IELVault(vaultContractAddress).claimDaoRewards(daoVaultAddress);

        emit DaoClaimRewards(operatorId, daoRewards);
    }

    function _settle(uint256 operatorId) internal {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();
    }

    function getTotalEthValue() public view returns (uint256) {
        return operatorPoolBalancesSum + beaconOracleContract.getBeaconBalances()
            + beaconOracleContract.getPendingBalances();
    }

    function getEthOut(uint256 _nethAmountIn) public view returns (uint256) {
        uint256 totalEth = getTotalEthValue();
        uint256 nethSupply = nETHContract.totalSupply();
        if (nethSupply == 0) {
            return _nethAmountIn;
        }

        return _nethAmountIn * (totalEth) / (nethSupply);
    }

    function getNethOut(uint256 _ethAmountIn) public view returns (uint256) {
        uint256 totalEth = getTotalEthValue();
        uint256 nethSupply = nETHContract.totalSupply();
        if (nethSupply == 0) {
            return _ethAmountIn;
        }
        require(totalEth > 0, "Cannot calculate nETH token amount while balance is zero");
        return _ethAmountIn * (nethSupply) / (totalEth);
    }

    function getExchangeRate() external view returns (uint256) {
        return getEthOut(1 ether);
    }

    // The total number of validators currently owned by the stake pool
    function getLiquidValidatorsCount() public view returns (uint256) {
        return getLiquidNfts().length;
    }

    // Validators currently owned by the stake pool
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
     * @notice set dao vault address
     */
    function setDaoAddress(address _dao) external onlyDao {
        dao = _dao;
    }

    function setDepositFeeRate(uint256 _feeRate) external onlyDao {
        require(_feeRate <= 1000, "Rate too high");
        depositFeeRate = _feeRate;
    }

    function setUnstakeFeeRate(uint256 _feeRate) external onlyDao {
        require(_feeRate <= 1000, "Rate too high");
        unstakeFeeRate = _feeRate;
    }

    function setLiquidStakingWithdrawalCredentials(bytes memory _liquidStakingWithdrawalCredentials) external onlyDao {
        liquidStakingWithdrawalCredentials = _liquidStakingWithdrawalCredentials;
    }

    function transfer(uint256 amount, address to) internal {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }

    function getOperatorPoolEtherMultiple(uint256 operator) internal view returns (uint256) {
        return operatorPoolBalances[operator] / DEPOSIT_SIZE;
    }

    function setBeaconOracleContract(address _beaconOracleContractAddress) external onlyDao {
        beaconOracleContract = IBeaconOracle(_beaconOracleContractAddress);
    }

    function setNodeOperatorRegistryContract(address _nodeOperatorRegistryContract) external onlyDao {
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContract);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    function receiveRewards(uint256 rewards) external payable {
        totalReinvestRewardsSum += rewards;
        emit RewardsReceive(rewards);
    }

    function slashReceive(uint256 amount) external payable {
        emit SlashReceive(amount);
    }

    function isPaused() public view returns (bool) {
        paused();
    }

    function pause() external onlyDao {
        _pause();
    }

    function unpause() external onlyDao {
        _unpause();
    }
}
