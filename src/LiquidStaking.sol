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


contract LiquidStaking2 is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
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
    mapping(uint256 => bool) private _liquidUserNft; // 从质押池使用neth买走的nft
    mapping(uint256 => bool) private _liquidTruestOperators; // 曾经拥有过的可信operator


    uint256 public unstakePoolSize; // nETH unstake pool，初始为0
    mapping(uint256 => uint256) public operatorPoolBalances; // operator的私有质押池子，key 是 operator_id

    uint256 public wrapOperator = 1; // 下次买nft时，卖出nft的operator id
    uint256 public nftWrapNonce;
    // dao address
    address public dao;
    // dao treasury address
    address public daoValutAddress;

    modifier onlyDao() {
        require(msg.sender == dao, "AUTH_FAILED");
        _;
    }

    event ELRewardsReceived(uint256 balance);
    event EtherDeposited(address from, uint256 balance, uint256 height);
    event Eth32Deposit(bytes _pubkey, bytes _withdrawal, address _owner);
    event Transferred(address _to, uint256 _amount);

    // todo withdrawalCreds 必须是本合约地址
    function initialize(
        address _dao,
        address _daoValutAddress,
        bytes memory withdrawalCreds,
        address _nodeOperatorRegistryContractAddress,
        address _nETHContractAddress,
        address _nVNFTContractAddress,
        address _beaconOracleContractAddress,
        address _depositContractAddress
    ) external
    initializer
    {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        dao = _dao;
        daoValutAddress = _daoValutAddress;

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

    event EthStake(address indexed from, uint256 amount, address indexed _referral, uint256 amountOut);
    function stakeETH(address _referral, uint256 _operatorId) external payable nonReentrant {
        require(msg.value >= 1000 wei, "Stake amount must be minimum  1000 wei");
        require(_referral != address(0), "Referral address must be provided");

        uint256 depositAmount;
        if(depositFeeRate == 0){
            depositAmount = msg.value;
        } else {
            depositAmount = depositFeeRate / totalBasisPoints * msg.value;
            transfer(msg.value - depositAmount, daoValutAddress);
        }

        operatorPoolBalances[_operatorId] = operatorPoolBalances[_operatorId] + depositAmount;

        // 1. 将depositAmount根据nETH的汇率进行换算
        // 2. 铸造nETH，todo nETH合约还未完，并且暂不确定：erc20是单独一个合约好 还是与质押池在一起好，在一起能够减少多次跨合约调用 ？？ lido rockpool - rebase
        uint256 amountOut = getNethOut(depositAmount);
        nETHContract.whiteListMint(amountOut, _referral);

        emit EthStake(msg.sender, msg.value, _referral, amountOut);
    }

    event EthUnstake(address indexed from, uint256 amount, address indexed _referral, uint256 amountOut);
    function unstakeETH(address _referral, uint256 amount) external nonReentrant {
        uint256 amountOut = getEthOut(amount);
        require(address(this).balance >= amountOut, "UNSTAKE_POOL_INSUFFICIENT_BALANCE");

        // 1.燃烧掉该用户的nETH
        // 2.将eth转移给该用户

        nETHContract.whiteListBurn(amount, msg.sender);
        transfer(amountOut, _referral);

        emit EthUnstake(msg.sender, amount, _referral, amountOut);
    }

    event NftStake(address indexed from, uint256 count);
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
            require(data[i].length == 320, "Invalid Data Length");
            bool trusted = _stake(data[i]);

            uint256 amountOut = getNethOut(DEPOSIT_SIZE);
            // mint nft / neth
            if (trusted) {
                uint256 _operatorId = uint256(bytes32(data[i][0:32]));
                bytes calldata pubkey = data[i][32:80];
                vNFTContract.whiteListMint(pubkey, msg.sender, _operatorId);
                uint256 tokenId = vNFTContract.getLatestTokenId();
                trustedNft[tokenId]= _operatorId;
                nETHContract.whiteListMint(amountOut, address(this));
                if (!_liquidTruestOperators[_operatorId]) {
                    _liquidTruestOperators[_operatorId] = true;
                }
                _settle(_operatorId);
            } else {
                nETHContract.whiteListMint(amountOut, address(this));
            }
            
            total_ether += DEPOSIT_SIZE;
        }

        require(msg.value == total_ether, "Incorrect Ether amount provided");

        emit NftStake(msg.sender, total_ether/DEPOSIT_SIZE);
        return true;
    }

    event ValidatorRegistered(uint256 operator, uint256 tokenId);
    // 不支持一次注册多个，因为为了保护untake pool
    function registerValidator(bytes calldata data) external nonReentrant {
        // 1. 解析data获得operator_id
        // 2. 检查operator_id是否可信
        // 3. precheck，需增加检查 withdrawalCredentials必须是质押池设置的
        // 4. signercheck
        // 5. depost
        // 6. operatorPoolBalances[_operatorId] = operatorPoolBalances[_operatorId] - depositAmount;
        // 7.mint nft，铸造nft，存放在质押池合约，不能再铸造neth，因为已经在用户deposit时完成铸造
        // 8.更新_liquidNfts
        uint256 _operatorId = uint256(bytes32(data[0:32]));
        require(address(this).balance >= unstakePoolSize, "UNSTAKE_POOL_INSUFFICIENT_BALANCE");
        require(nodeOperatorRegistryContract.isTrustedOperator(_operatorId) == true, "The operator must be trusted");
        operatorPoolBalances[_operatorId] = operatorPoolBalances[_operatorId] - DEPOSIT_SIZE;

        _stake(data);
        _settle(_operatorId);

        // mint nft 
        vNFTContract.whiteListMint(data[32:80], address(this), _operatorId);
        uint256 tokenId = vNFTContract.getLatestTokenId();
        trustedNft[tokenId]= _operatorId;
        _liquidNfts.push(tokenId);
        _operatorNfts[_operatorId].push(tokenId);
        if (!_liquidTruestOperators[_operatorId]) {
            _liquidTruestOperators[_operatorId] = true;
        }
        
        emit ValidatorRegistered(_operatorId, tokenId);
    }

    function _stake(bytes calldata data) internal returns (bool) {
        uint256 _operatorId = uint256(bytes32(data[0:32]));
        uint256 operatorsCount = nodeOperatorRegistryContract.getNodeOperatorsCount();
        require(_operatorId <= operatorsCount, "The operator does not exist");

        bool trusted;
        address controllerAddress;
        (trusted, , , controllerAddress, ) = nodeOperatorRegistryContract.getNodeOperator(_operatorId, false);
        bytes32 hash = precheck(data); // todo 数据位置
        signercheck(bytes32(data[256:288]), bytes32(data[288:320]), uint8(bytes1(data[1])), hash, controllerAddress); // todo 数据位置
        deposit(data);

        return trusted;
    }

    /**
     * @notice Pre-processing before performing the signer verification.  
     * @return bytes32 hashed value of the pubkey, withdrawalCredentials, signature,
     *         depositDataRoot, bytes32(blockNumber)
     */
    function precheck(bytes calldata data) private view returns (bytes32) {
        bytes calldata withdrawalCredentials = data[64:96];
        // todo 判断是否相等
        // require(withdrawalCredentials == liquidStakingWithdrawalCredentials, "withdrawal credentials does not match");

        bytes calldata pubkey = data[16:64];
        bytes calldata signature = data[96:192];
        bytes32 depositDataRoot = bytes32(data[192:224]);
        uint256 blockNumber = uint256(bytes32(data[224:256]));

        require(!vNFTContract.validatorExists(pubkey), "Pub key already in used");
        require(blockNumber > block.number, "Block height too old, please generate a new transaction");

        return keccak256(abi.encodePacked(pubkey, withdrawalCredentials, signature, depositDataRoot, bytes32(blockNumber)));
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

    event NftWrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    // 将neth兑换成nft
    function wrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant {
        // 1.检查token id对应的wrapOperator 是否正确
        // 2.检查value 和预言机是否匹配
        // 3.检查neth余额是否满足 - 不需要
        // 4.将用户neth转移到质押池
        // 5.触发一次 operator的 claim，将nft转移给用户
        // 6.将wrapOperator递增循环
        // 7.记录_liquidUserNft为true
        // 8.将valut合约setUserNft 为block.number

        uint256 operatorId = vNFTContract.operatorOf(tokenId);
        require(operatorId == wrapOperator, "The selected token id does not belong to the operator being sold");

        uint256 amountOut = getNethOut(value);

        bytes memory pubkey = vNFTContract.validatorOf(tokenId);
        bool success = beaconOracleContract.verifyNftValue(proof, pubkey, value, tokenId);
        require(success, "verifyNftValue fail");

        success = nETHContract.transferFrom(msg.sender, address(this), amountOut);
        require(success, "Failed to transfer neth");

        claimRewardsOfOperator(operatorId);

        vNFTContract.safeTransferFrom(address(this), msg.sender, tokenId);

        if (wrapOperator == nodeOperatorRegistryContract.getNodeOperatorsCount()) {
            wrapOperator = 1;
        }else {
            wrapOperator = wrapOperator + 1;
        }

        _liquidUserNft[tokenId] = true;

        address valutContractAddress;
        (, , , , valutContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        IELVault(valutContractAddress).setUserNft(tokenId, block.number);
        nftWrapNonce = nftWrapNonce + 1;

        emit NftWrap(tokenId, operatorId, value, amountOut);
    }

    event NftUnwrap(uint256 tokenId, uint256 operatorId, uint256 value, uint256 amountOut);
    // 将nft兑换成neth
    function unwrapNFT(uint256 tokenId, bytes32[] memory proof, uint256 value) external nonReentrant {
        // 1.检查发起者是否持有token_id - 不需要
        // 2.检查value与预言机是否匹配
        // 3.检查token_id是否存在于trustedNft，存在直接转neth，更新_liquidUserNft 为false；不存在重新铸造neth并将tokenid记录到trustedNft，并增加_liquidNfts
        // 4.替用户 claim收益，将用户nft转移到质押池
        // 5.将neth转移给用户
        // 6.将valut合约setUserNft 为 0
        uint256 operatorId = vNFTContract.operatorOf(tokenId);

        bool trusted;
        address valutContractAddress;
        (trusted, , , , valutContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        require(trusted, "permission denied");

        bytes memory pubkey = vNFTContract.validatorOf(tokenId);
        bool success = beaconOracleContract.verifyNftValue(proof, pubkey, value, tokenId);
        require(success, "verifyNftValue fail");

        uint256 amountOut = getNethOut(value);

        if (trustedNft[tokenId] != 0) { // operator 不能等于0
            _liquidUserNft[tokenId] = false;
        } else {
            nETHContract.whiteListMint(amountOut, msg.sender);
            trustedNft[tokenId] = operatorId;
            _liquidNfts.push(tokenId);
        }

        claimRewardsOfUser(tokenId);

        vNFTContract.safeTransferFrom(msg.sender, address(this), tokenId);
        
        success = nETHContract.transferFrom(msg.sender, address(this), amountOut);
        require(success, "Failed to transfer neth");
        
        IELVault(valutContractAddress).setUserNft(tokenId, 0);
        nftWrapNonce = nftWrapNonce + 1;
        
        emit NftUnwrap(tokenId, operatorId, value, amountOut);
    }

    event OperatorClaimRewards(uint256 operatorId, uint256 rewards);
    function claimRewardsOfOperator(uint256 operatorId) public { 
        // 1.claim 收益 复投 operatorPoolBalances
        // 2.结算完收益 setLiquidStakingGasHeight

        address valutContractAddress;
        (, , , , valutContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        IELVault(valutContractAddress).settle();

        uint256[] memory nfts = getOperatorNfts(operatorId);
        
        uint256 nftRewards = IELVault(valutContractAddress).claimRewardsOfLiquidStaking(nfts);
        IELVault(valutContractAddress).setLiquidStakingGasHeight(block.number);
    
        operatorPoolBalances[operatorId] = operatorPoolBalances[operatorId] + nftRewards;

        emit OperatorClaimRewards(operatorId, nftRewards);
    }
    
    event UserClaimRewards(uint256 operatorId, uint256 rewards);
    function claimRewardsOfUser(uint256 tokenId) public {
        // 收益转给用户
        uint256 operatorId = vNFTContract.operatorOf(tokenId);
        address valutContractAddress;
        (, , , , valutContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        IELVault(valutContractAddress).settle();

        uint256 nftRewards = IELVault(valutContractAddress).claimRewardsOfUser(tokenId);

        emit UserClaimRewards(operatorId, nftRewards);
    }

    function _settle(uint256 operatorId) internal {
        address valutContractAddress;
        (, , , , valutContractAddress) = nodeOperatorRegistryContract.getNodeOperator(operatorId, false);
        IELVault(valutContractAddress).settle();
    }

    // todo 与neth之间的调用关系，以及rebase逻辑
    function getTotalEthValue() public view returns(uint256) {
        uint256 beaconBalance = beaconOracleContract.beaconValue();

        uint256 i;
        uint256 operators = nodeOperatorRegistryContract.getNodeOperatorsCount();
        address valutContractAddress;
        uint256 totalReward;
        for (i = 0; i < operators; i++) {
            if (_liquidTruestOperators[i]) {
                (, , , , valutContractAddress) = nodeOperatorRegistryContract.getNodeOperator(i, false);
                uint256[] memory nfts = getOperatorNfts(i);
                uint256 nftRewards = IELVault(valutContractAddress).batchRewards(nfts);
                totalReward += nftRewards;
            }
        }
        
        return beaconBalance + totalReward + address(this).balance;
    }

    
    function getEthOut(uint256 _nethAmountIn) public view returns(uint256) {
        uint256 totalEth = getTotalEthValue();
        uint256 nethSupply = nETHContract.totalSupply();
        if (nethSupply == 0) {
            return _nethAmountIn;
        }

        return _nethAmountIn * (totalEth) / (nethSupply);
    }


    function getNethOut(uint256 _ethAmountIn) public view returns(uint256) {
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
    function getLiquidValidatorsCount() public view returns(uint256) {
        return getLiquidNfts().length;
    }

    // 质押池当前拥有的验证者
    function getLiquidNfts() public view returns(uint256[] memory) {
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

    function getOperatorNfts(uint256 operatorId) public view returns(uint256[] memory) {
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
      * @notice set dao valut address
      */
    function setDaoAddress(address _dao) external onlyDao {
        dao = _dao;
    }

    function setUnstakePoolSize(uint256 _unstakePoolSize)public onlyDao {
        unstakePoolSize = _unstakePoolSize;
    }

    function setDepositFeeRate(uint256 _feeRate) external onlyDao {
        require(_feeRate < totalBasisPoints, "cannot be 100%");
        depositFeeRate = _feeRate;
    }

    function setLiquidStakingWithdrawalCredentials(bytes memory _liquidStakingWithdrawalCredentials)  external onlyDao {
        liquidStakingWithdrawalCredentials = _liquidStakingWithdrawalCredentials;
    }

    function transfer(uint256 amount, address to) private {
        require(to != address(0), "Recipient address provided invalid");
        payable(to).transfer(amount);
        emit Transferred(to, amount);
    }
}
