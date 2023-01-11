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

    bytes public liquidStakingWithdrawalCredentials; // 通过质押池质押出去的验证者使用

    uint256 public depositFeeRate; // 质押fee率，初期设为0，后期根据需要更改
    uint256 public constant totalBasisPoints = 10000;

    uint256 public constant DEPOSIT_SIZE = 32 ether; // 质押金额

    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    address public nodeOperatorRegistryContractAddress;

    INETH public nETHContract;
    address public nETHContractAddress;

    IVNFT public vNFTContract;
    address public vNFTContractAddress;

    IBeaconOracle public beaconOracleContract;
    address public beaconOracleContractAddress;

    mapping(uint256 => uint256) public trustedNft; // 白名单nft，此nft均已铸造neth，key 是 token_id，value是operator_id

    uint256[] private _liquidNfts; // 质押池拥有过的验证者tokenid，trustedNft包含可能大于liquidNfts，因为用户手里可能会有
    mapping(uint256 => uint256[]) private _operatorNfts; //
    mapping(uint256 => bool) private _liquidUserNft;
    // 从质押池使用neth买走的nft
    mapping(uint256 => bool) private _liquidTruestOperators; // 曾经拥有过的可信operator，存在可信operator被移除可信列表，但他已经注册的白名单nft要统计价值

    uint256 public unstakePoolSize; // nETH unstake pool，初始为0
    mapping(uint256 => uint256) public operatorPoolBalances; // operator的私有质押池子，key 是 operator_id

    uint256 public wrapOperator = 1; // 下次买nft时，卖出nft的operator id
    uint256 public nftWrapNonce;
    // dao address
    address public dao;
    // dao treasury address
    address public daoVaultAddress;

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    event EthStake(address indexed from, uint256 amount, address indexed _referral, uint256 amountOut);
    event EthUnstake(address indexed from, uint256 amount, address indexed _referral, uint256 amountOut);
    event NftStake(address indexed from, uint256 count);
    event Eth32Deposit(bytes _pubkey, bytes _withdrawal, address _owner);
    event ValidatorRegistered(uint256 operator, uint256 tokenId);
    event NftWrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event NftUnwrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    event OperatorClaimRewards(uint256 operatorId, uint256 rewards);
    event UserClaimRewards(uint256 operatorId, uint256 rewards);
    event Transferred(address _to, uint256 _amount);

    // todo withdrawalCreds 是一个共识层的提款地址
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

        // 1. 将depositAmount根据nETH的汇率进行换算
        // 2. 铸造nETH
        uint256 amountOut = getNethOut(depositPoolAmount);
        nETHContract.whiteListMint(amountOut, _referral);

        emit EthStake(msg.sender, msg.value, _referral, amountOut);
    }

    function unstakeETH(address _referral, uint256 amount) external nonReentrant {
        uint256 amountOut = getEthOut(amount);
        require(address(this).balance >= amountOut, "UNSTAKE_POOL_INSUFFICIENT_BALANCE");

        // 1.燃烧掉该用户的nETH
        // 2.将eth转移给该用户

        nETHContract.whiteListBurn(amount, msg.sender);
        transfer(amountOut, _referral);

        emit EthUnstake(msg.sender, amount, _referral, amountOut);
    }

    // 0:2 v
    // 2:14 empty
    // 16:64 pubkey
    // 64:96 withdrawalCredentials
    // 96:192 signature
    // 192:224 depositDataRoot
    // 224:256 blockNumber
    // 256:288 s
    // 288:320 r
    // 320:352 operatorId
    // 支持一个注册多个，必须operator提供签名
    function stakeNFT(bytes[] calldata data) external payable nonReentrant returns (bool) {
        // 1.判断资金
        // 2.operator检查，必须存在
        // 3.precheck，需增加检查 withdrawalCredentials必须是质押池设置的
        // 4.signercheck
        // 5.depost
        // 6.mint nft，如果是可信operator，为质押池铸造neth，nft转移给用户，nft记录于trustedNft；如果是非可信operator，只铸造nft

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

    // 1. 解析data获得operator_id
    // 2. 检查operator_id是否可信
    // 3. precheck，需增加检查 withdrawalCredentials必须是质押池设置的
    // 4. signercheck
    // 5. depost
    // 6. operatorPoolBalances[_operatorId] = operatorPoolBalances[_operatorId] - depositAmount;
    // 7.mint nft，铸造nft，存放在质押池合约，不能再铸造neth，因为已经在用户deposit时完成铸造
    // 8.更新_liquidNfts
    function registerValidator(
        uint256 operatorId,
        bytes calldata withdrawalCredentials,
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) external nonReentrant {
        bool trusted;
        address controllerAddress;
        (trusted,,, controllerAddress,) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        require(trusted, "The operator must be trusted");
        require(msg.sender == controllerAddress, "msg.sender must be the controllerAddress of the operator");
        require(getOperatorPoolEtherMultiple(operatorId) >= pubkeys.length, "Insufficient balance");
        require(
            keccak256(abi.encodePacked(withdrawalCredentials))
                == keccak256(abi.encodePacked(liquidStakingWithdrawalCredentials)),
            "withdrawal credentials does not match"
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

    // 暂不支持
    function unstakeNFT(bytes[] calldata data) public nonReentrant returns (bool) {
        return data.length == 0;
    }

    // 将neth兑换成nft
    function wrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant {
        // 1.检查token id对应的wrapOperator 是否正确
        // 2.检查value 和预言机是否匹配
        // 3.检查neth余额是否满足 - 不需要
        // 4.将用户neth转移到质押池
        // 5.触发一次 operator的 claim，将nft转移给用户
        // 6.将wrapOperator递增循环
        // 7.记录_liquidUserNft为true
        // 8.将vault合约setUserNft 为block.number

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

    // 将nft兑换成neth
    function unwrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant {
        // 1.检查发起者是否持有token_id - 不需要
        // 2.检查value与预言机是否匹配
        // 3.检查token_id是否存在于trustedNft，存在直接转neth，更新_liquidUserNft 为false；不存在重新铸造neth并将tokenid记录到trustedNft，并增加_liquidNfts
        // 4.替用户 claim收益，将用户nft转移到质押池
        // 5.将neth转移给用户
        // 6.将vault合约setUserNft 为 0
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
            // operator 不能等于0
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

    function batchClaimRewardsOfOperator(uint256[] memory operatorIds) public {
        // 1.claim 收益 复投 operatorPoolBalances
        // 2.结算完收益 setLiquidStakingGasHeight
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

    function claimRewardsOfOperator(uint256 operatorId) public {
        // todo 领多个 batch_
        // 1.claim 收益 复投 operatorPoolBalances
        // 2.结算完收益 setLiquidStakingGasHeight

        address vaultContractAddress = nodeOperatorRegistryContract.getNodeOperatorVaultContract(operatorId);
        IELVault(vaultContractAddress).settle();

        uint256 nftRewards = IELVault(vaultContractAddress).claimRewardsOfLiquidStaking();
        IELVault(vaultContractAddress).setLiquidStakingGasHeight(block.number);

        operatorPoolBalances[operatorId] = operatorPoolBalances[operatorId] + nftRewards;

        emit OperatorClaimRewards(operatorId, nftRewards);
    }

    function claimRewardsOfUser(uint256 tokenId) public {
        // 收益转给用户
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

    // 质押池当前拥有的验证者总数
    function getLiquidValidatorsCount() public view returns (uint256) {
        return getLiquidNfts().length;
    }

    // 质押池当前拥有的验证者
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
