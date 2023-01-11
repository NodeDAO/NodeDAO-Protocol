// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/INETH.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/IDepositContract.sol";
import "src/interfaces/IBeaconOracle.sol";
import "src/interfaces/IELVault.sol";

contract LiquidStaking is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    IDepositContract public depositContract;

    bytes public liquidStakingWithdrawalCredentials;

    uint256 public depositFeeRate; //deposit fee rate,
    uint256 public constant totalBasisPoints = 10000;

    uint256 public constant DEPOSIT_SIZE = 32 ether;

    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    address public nodeOperatorRegistryContractAddress;

    INETH public nETHContract;
    address public nETHContractAddress;

    IVNFT public vNFTContract;
    address public vNFTContractAddress;

    IBeaconOracle public beaconOracleContract;
    address public beaconOracleContractAddress;

    mapping(uint256 => uint256) public trustedNft; // trusted nft, this nft has already minted neth, key is token_id, value is operator_id

    uint256[] private _liquidNfts; // The validator tokenid owned by the stake pool, trustedNft may be greater than liquidNfts, because the user may have
    mapping(uint256 => uint256[]) private _operatorNfts;
    mapping(uint256 => bool) private _liquidUserNft; // The nft purchased from the staking pool using neth
    mapping(uint256 => bool) private _liquidTruestOperators; // once owned trusted operator

    uint256 public unstakePoolSize; // nETH unstake pool
    mapping(uint256 => uint256) public operatorPoolBalances; // operator's private stake pool, key is operator_id

    uint256 public wrapOperator = 1; // When buying nft next time, sell the operator id of nft
    uint256 public nftWrapNonce;
    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    event EthStake(address indexed from, uint256 amount, uint256 amountOut, address indexed _referral);
    event EthUnstake(address indexed from, uint256 amount, uint256 amountOut);
    event NftStake(address indexed from, uint256 count);
    event Eth32Deposit(bytes _pubkey, bytes _withdrawal, address _owner);
    event ValidatorRegistered(uint256 operator, uint256 tokenId);
    event NftWrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event NftUnwrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event OperatorClaimRewards(uint256 operatorId, uint256 rewards);
    event UserClaimRewards(uint256 operatorId, uint256 rewards);
    event Transferred(address _to, uint256 _amount);

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

        dao = _dao;
        daoVaultAddress = _daoVaultAddress;

        liquidStakingWithdrawalCredentials = withdrawalCreds;

        depositContract = IDepositContract(_depositContractAddress);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryContractAddress);
        nodeOperatorRegistryContractAddress = _nodeOperatorRegistryContractAddress;

        nETHContract = INETH(_nETHContractAddress);
        nETHContractAddress = _nETHContractAddress;

        vNFTContract = IVNFT(_nVNFTContractAddress);
        vNFTContractAddress = _nVNFTContractAddress;

        beaconOracleContract = IBeaconOracle(_beaconOracleContractAddress);
        beaconOracleContractAddress = _beaconOracleContractAddress;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function stakeETH(address _referral, uint256 _operatorId) external payable nonReentrant {
        require(msg.value >= 1000 wei, "Stake amount must be minimum  1000 wei");
        require(_referral != address(0), "Referral address must be provided");
        require(
            nodeOperatorRegistryContract.isTrustedOperator(_operatorId) == true,
            "The message sender is not part of Trusted KingHash Operators"
        );

        uint256 depositFeeAmount;
        uint256 depositPoolAmount;
        if (depositFeeRate == 0) {
            depositPoolAmount = msg.value;
        } else {
            depositFeeAmount = msg.value * depositFeeRate / totalBasisPoints;
            depositPoolAmount = msg.value - depositFeeAmount;
            transfer(depositFeeAmount, daoVaultAddress);
        }

        operatorPoolBalances[_operatorId] += depositPoolAmount;

        // 1. Convert depositAmount according to the exchange rate of nETH
        // 2. Mint nETH
        uint256 amountOut = getNethOut(depositPoolAmount);
        nETHContract.whiteListMint(amountOut, msg.sender);

        emit EthStake(msg.sender, msg.value, amountOut, _referral);
    }

    //1. Burn the user's nETH
    //2. Transfer eth to the user
    function unstakeETH(uint256 amount) external nonReentrant {
        uint256 amountOut = getEthOut(amount);
        require(address(this).balance >= amountOut, "UNSTAKE_POOL_INSUFFICIENT_BALANCE");

        nETHContract.whiteListBurn(amount, msg.sender);
        transfer(amountOut, msg.sender);

        emit EthUnstake(msg.sender, amount, amountOut);
    }

    //1. Determine funds
    //2. operator check, must exist
    //3. precheck, need to add check withdrawalCredentials must be set by the stake pool
    //4. signercheck
    //5. depost
    //6. mint nft, if it is a trusted operator, mint neth for the stake pool, transfer nft to the user, and record nft in trustedNft; if it is an untrusted operator, only mint nft
    function stakeNFT(bytes[] calldata data) external payable nonReentrant returns (bool) {
        uint256 total_ether = 0;
        for (uint256 i = 0; i < data.length; i++) {
            require(data[i].length == 352, "Invalid Data Length");
            bool trusted = _stake(data[i]);

            uint256 amountOut = getNethOut(DEPOSIT_SIZE);
            // mint nft / neth
            if (trusted) {
                uint256 _operatorId = uint256(bytes32(data[i][320:352]));
                bytes calldata pubkey = data[i][16:64];
                vNFTContract.whiteListMint(pubkey, msg.sender, _operatorId);
                uint256 tokenId = vNFTContract.getLatestTokenId();
                trustedNft[tokenId] = _operatorId;
                nETHContract.whiteListMint(amountOut, address(this));
                if (!_liquidTruestOperators[_operatorId]) {
                    _liquidTruestOperators[_operatorId] = true;
                }
                _settle(_operatorId);

                address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(_operatorId);
                IELVault(vaultContractAddress).setUserNft(tokenId, block.number);
            } else {
                nETHContract.whiteListMint(amountOut, address(this));
            }

            total_ether += DEPOSIT_SIZE;
        }

        require(msg.value == total_ether, "Incorrect Ether amount provided");

        emit NftStake(msg.sender, total_ether / DEPOSIT_SIZE);
        return true;
    }

    function _stake(bytes calldata data) internal returns (bool) {
        uint256 _operatorId = uint256(bytes32(data[320:352]));
        uint256 operatorsCount = nodeOperatorRegistryContract.getNodeOperatorsCount();
        require(_operatorId <= operatorsCount, "The operator does not exist");

        bool trusted;
        address controllerAddress;
        (trusted,,, controllerAddress,) = nodeOperatorRegistryContract.getNodeOperator(_operatorId, false);
        bytes32 hash = precheck(data);
        signercheck(bytes32(data[256:288]), bytes32(data[288:320]), uint8(bytes1(data[1])), hash, controllerAddress);
        deposit(data);

        return trusted;
    }

    //1. Check whether msg.sender is the controllerAddress of the operator
    //2. Check if operator_id is trusted
    //3. precheck, need to add check withdrawalCredentials must be set by the stake pool
    //4. signercheck
    //5. depost
    //6. operatorPoolBalances[_operatorId] = operatorPoolBalances[_operatorId] -depositAmount;
    //7. mint nft, minting nft, stored in the stake pool contract, can no longer mint neth, because minting has been completed when the user deposits
    //8. Update _liquidNfts
    function registerValidator(
        bytes calldata withdrawalCredentials,
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) external nonReentrant {
        uint256 operatorId = nodeOperatorRegistryContract.isTrustedOperator(msg.sender);
        require(
            operatorId != 0,
            "msg.sender must be the controllerAddress of the trusted operator"
        );
        require(getOperatorPoolEtherMultiple(operatorId) >= pubkeys.length, "Insufficient balance");
        require(
            keccak256(abi.encodePacked(withdrawalCredentials))
                == keccak256(abi.encodePacked(liquidStakingWithdrawalCredentials)),
            "withdrawal credentials does not match"
        );
        require(
            address(this).balance >= unstakePoolSize + DEPOSIT_SIZE * pubkeys.length,
            "UNSTAKE_POOL_INSUFFICIENT_BALANCE"
        );

        uint256 i;
        for (i = 0; i < pubkeys.length; i++) {
            bytes calldata withdrawalCredential = withdrawalCredentials;
            _stakeAndMint(operatorId, pubkeys[i], signatures[i], depositDataRoots[i], withdrawalCredential);
        }

        operatorPoolBalances[operatorId] -= DEPOSIT_SIZE * pubkeys.length;
        _settle(operatorId);
    }

    function _stakeAndMint(
        uint256 operatorId,
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot,
        bytes calldata withdrawalCredential
    ) internal {
        depositContract.deposit{value: 32 ether}(pubkey, withdrawalCredential, signature, depositDataRoot);

        // mint nft
        vNFTContract.whiteListMint(pubkey, address(this), operatorId);
        uint256 tokenId = vNFTContract.getLatestTokenId();
        trustedNft[tokenId] = operatorId;
        _liquidNfts.push(tokenId);
        _operatorNfts[operatorId].push(tokenId);
        if (!_liquidTruestOperators[operatorId]) {
            _liquidTruestOperators[operatorId] = true;
        }

        emit ValidatorRegistered(operatorId, tokenId);
    }

    /**
     * @notice Pre-processing before performing the signer verification.
     * @return bytes32 hashed value of the pubkey, withdrawalCredentials, signature,
     *         depositDataRoot, bytes32(blockNumber)
     */
    function precheck(bytes calldata data) private view returns (bytes32) {
        bytes calldata withdrawalCredentials = data[64:96];
        require(
            keccak256(abi.encodePacked(withdrawalCredentials))
                == keccak256(abi.encodePacked(liquidStakingWithdrawalCredentials)),
            "withdrawal credentials does not match"
        );
        bytes calldata pubkey = data[16:64];
        bytes calldata signature = data[96:192];
        bytes32 depositDataRoot = bytes32(data[192:224]);
        uint256 blockNumber = uint256(bytes32(data[224:256]));

        require(!vNFTContract.validatorExists(pubkey), "Pub key already in used");
        require(blockNumber > block.number, "Block height too old, please generate a new transaction");

        return
            keccak256(abi.encodePacked(pubkey, withdrawalCredentials, signature, depositDataRoot, bytes32(blockNumber)));
    }

    /**
     * @notice Performs signer verification to prevent unauthorized usage
     * @param v, r, and s parts of a signature
     * @param hash_ - hashed value from precheck
     * @param signer_ - authentic signer to check against
     */
    function signercheck(bytes32 s, bytes32 r, uint8 v, bytes32 hash_, address signer_) private pure {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, hash_));
        address signer = ecrecover(prefixedHash, v, r, s);

        require(signer == signer_, "Not authorized");
        require(signer != address(0), "ECDSA: invalid signature");
    }

    /**
     * @notice Allows transfer funds of 32 ETH to the ETH2 Official Deposit Contract
     */
    //slither-disable-next-line reentrancy-events
    function deposit(bytes calldata data) private {
        bytes calldata pubkey = data[16:64];
        bytes calldata withdrawalCredentials = data[64:96];
        bytes calldata signature = data[96:192];
        bytes32 depositDataRoot = bytes32(data[192:224]);

        depositContract.deposit{value: 32 ether}(pubkey, withdrawalCredentials, signature, depositDataRoot);

        emit Eth32Deposit(pubkey, withdrawalCredentials, msg.sender);
    }

    function unstakeNFT(bytes[] calldata data) public nonReentrant returns (bool) {
        return data.length == 0;
    }

    //wrap neth to nft
    //1. Check whether the wrapOperator corresponding to the token id is correct
    //2. Check if the value matches the oracle
    //3. Check if the neth balance is satisfied -not required
    //4. Transfer user neth to the stake pool
    //5. Trigger the operator's claim once, and transfer the nft to the user
    //6. Increment wrapOperator loop
    //7. Record _liquidUserNft as true
    //8. Set the vault contract setUserNft to block.number
    function wrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant {
        uint256 operatorId = vNFTContract.operatorOf(tokenId);
        require(operatorId == wrapOperator, "The selected token id does not belong to the operator being sold");

        uint256 amountOut = getNethOut(value);

        bytes memory pubkey = vNFTContract.validatorOf(tokenId);
        bool success = beaconOracleContract.verifyNftValue(proof, pubkey, value, tokenId);
        require(success, "verifyNftValue fail");

        success = nETHContract.transferFrom(msg.sender, address(this), amountOut);
        require(success, "Failed to transfer neth");

        _settle(operatorId);
        claimRewardsOfOperator(operatorId);

        vNFTContract.safeTransferFrom(address(this), msg.sender, tokenId);

        if (wrapOperator == nodeOperatorRegistryContract.getNodeOperatorsCount()) {
            wrapOperator = 1;
        } else {
            wrapOperator = wrapOperator + 1;
        }

        _liquidUserNft[tokenId] = true;

        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).setUserNft(tokenId, block.number);
        nftWrapNonce = nftWrapNonce + 1;

        emit NftWrap(tokenId, operatorId, value, amountOut);
    }

    //unwrap nft to neth
    //1. Check if the originator holds a token_id -not required
    //2. Check if the value matches the oracle
    //3. Check whether the token_id exists in trustedNft, if there is a direct transfer to neth, update _liquidUserNft to false; if there is no recasting of neth, record the tokenid to trustedNft, and add _liquidNfts
    //4. Claim income for the user, and transfer the user's nft to the stake pool
    //5. Transfer neth to the user
    //6. Set the vault contract setUserNft to 0
    function unwrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant {
        uint256 operatorId = vNFTContract.operatorOf(tokenId);

        bool trusted;
        address vaultContractAddress;
        (trusted,,,, vaultContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        require(trusted, "permission denied");

        bytes memory pubkey = vNFTContract.validatorOf(tokenId);
        bool success = beaconOracleContract.verifyNftValue(proof, pubkey, value, tokenId);
        require(success, "verifyNftValue fail");

        uint256 amountOut = getNethOut(value);

        if (trustedNft[tokenId] != 0) {
            _liquidUserNft[tokenId] = false;
        } else {
            nETHContract.whiteListMint(amountOut, msg.sender);
            trustedNft[tokenId] = operatorId;
            _liquidNfts.push(tokenId);
        }

        _settle(operatorId);
        claimRewardsOfUser(tokenId);

        vNFTContract.safeTransferFrom(msg.sender, address(this), tokenId);

        success = nETHContract.transferFrom(msg.sender, address(this), amountOut);
        require(success, "Failed to transfer neth");

        IELVault(vaultContractAddress).setUserNft(tokenId, 0);
        nftWrapNonce = nftWrapNonce + 1;

        emit NftUnwrap(tokenId, operatorId, value, amountOut);
    }

    //1. claim income operatorPoolBalances
    //2. Earnings are settled setLiquidStakingGasHeight
    function batchClaimRewardsOfOperator(uint256[] memory operatorIds) public {
        uint256 i;
        for (i = 0; i < operatorIds.length; i++) {
            address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorIds[i]);
            IELVault(vaultContractAddress).settle();

            uint256 nftRewards = IELVault(vaultContractAddress).claimRewardsOfLiquidStaking();
            IELVault(vaultContractAddress).setLiquidStakingGasHeight(block.number);

            operatorPoolBalances[operatorIds[i]] = operatorPoolBalances[operatorIds[i]] + nftRewards;

            emit OperatorClaimRewards(operatorIds[i], nftRewards);
        }
    }

    //1. claim income operatorPoolBalances
    //2. Earnings are settled setLiquidStakingGasHeight
    function claimRewardsOfOperator(uint256 operatorId) public {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();

        uint256 nftRewards = IELVault(vaultContractAddress).claimRewardsOfLiquidStaking();
        IELVault(vaultContractAddress).setLiquidStakingGasHeight(block.number);

        operatorPoolBalances[operatorId] = operatorPoolBalances[operatorId] + nftRewards;

        emit OperatorClaimRewards(operatorId, nftRewards);
    }

    function claimRewardsOfUser(uint256 tokenId) public {
        uint256 operatorId = vNFTContract.operatorOf(tokenId);
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();

        uint256 nftRewards = IELVault(vaultContractAddress).claimRewardsOfUser(tokenId);

        emit UserClaimRewards(operatorId, nftRewards);
    }

    function _settle(uint256 operatorId) internal {
        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();
    }

    function getTotalEthValue() public view returns (uint256) {
        uint256 beaconBalance = beaconOracleContract.getBeaconBalances();
        return beaconBalance + address(this).balance;
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
        uint256 nftCount;
        uint256[] memory liquidNfts;
        uint256 i;
        for (i = 0; i < _liquidNfts.length; i++) {
            uint256 tokenId = _liquidNfts[i];
            if (_liquidUserNft[tokenId]) {
                nftCount += 1;
            }
        }

        liquidNfts = new uint256[] (nftCount);
        for (i = 0; i < _liquidNfts.length; i++) {
            uint256 tokenId = _liquidNfts[i];
            if (_liquidUserNft[tokenId]) {
                liquidNfts[i] = tokenId;
            }
        }

        return liquidNfts;
    }

    function getOperatorNfts(uint256 operatorId) public view returns (uint256[] memory) {
        uint256 nftCount;
        uint256[] memory operatorNfts;

        uint256[] memory nfts = _operatorNfts[operatorId];
        uint256 i;
        for (i = 0; i < nfts.length; i++) {
            uint256 tokenId = nfts[i];
            if (_liquidUserNft[tokenId]) {
                nftCount += 1;
            }
        }

        operatorNfts = new uint256[] (nftCount);
        for (i = 0; i < nfts.length; i++) {
            uint256 tokenId = nfts[i];
            if (_liquidUserNft[tokenId]) {
                operatorNfts[i] = tokenId;
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

    function setUnstakePoolSize(uint256 _unstakePoolSize) public onlyDao {
        unstakePoolSize = _unstakePoolSize;
    }

    function setDepositFeeRate(uint256 _feeRate) external onlyDao {
        require(_feeRate < totalBasisPoints, "cannot be 100%");
        depositFeeRate = _feeRate;
    }

    function setLiquidStakingWithdrawalCredentials(bytes memory _liquidStakingWithdrawalCredentials) external onlyDao {
        liquidStakingWithdrawalCredentials = _liquidStakingWithdrawalCredentials;
    }

    function transfer(uint256 amount, address to) private {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }

    function getOperatorPoolEtherMultiple(uint256 operator) internal view returns (uint256) {
        return operatorPoolBalances[operator] / 32 ether;
    }
}
