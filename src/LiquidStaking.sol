// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INEth.sol";
import "src/interfaces/IBeaconOracle.sol";
import "src/interfaces/IVNFT.sol";

contract LiquidStaking is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable, ILiquidStaking {

    bytes private withdrawalCredentials;
    uint256 private totalBeaconValidators;
    bytes32 private nodeRankingCommitment;
    uint256 public constant depositSize = 32 ether;
    uint256 private depositFeeRate;
    uint256 public constant totalBasisPoints = 10000;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 private bufferedEtherPosition;
    uint256 private transientEtherPosition;
    uint256 private beaconEtherPosition;
    address oracleAddress;
    address nodeOperatorRegistryAddress;
    address nETHAddress;

    mapping(uint256 => uint256) public operatorPoolBalances;

    event DepositReceived(address indexed from, uint256 amount, address indexed _referral);
    event ELRewardsReceived(uint256 balance);
    event EtherDeposited(address from, uint256 balance, uint256 height);

    INodeOperatorsRegistry iNodeOperatorRegistry;
    INEth iNETH;
    IBeaconOracle iOracle;
    IVNFT iVNFT;

    function initialize(bytes memory withdrawalCreds, address _nodeOperatorRegistry, address _nETHAddress, address _oracleAddress, address _validatorNftAddress) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        withdrawalCredentials = withdrawalCreds;
        _setProtocolContracts(_nodeOperatorRegistry, _nETHAddress, _oracleAddress, _validatorNftAddress);
    }

    function _setProtocolContracts(  address _nodeOperatorRegistry, address _nETHAddress, address _oracleAddress, address _validatorNftAddress) internal {
        require(_nodeOperatorRegistry != address(0), "The Oracle Contract Address must be zero");
        require(_nETHAddress != address(0), "The Oracle Contract Address must be zero");
        require(_oracleAddress != address(0), "The Oracle Contract Address must be zero");
        oracleAddress = _oracleAddress;
        nodeOperatorRegistryAddress = _nodeOperatorRegistry;
        nETHAddress = _nETHAddress;
        iNodeOperatorRegistry = INodeOperatorsRegistry(_nodeOperatorRegistry);
        iNETH = INEth(_nETHAddress);
        iOracle = IBeaconOracle(_oracleAddress);
        iVNFT = IVNFT(_validatorNftAddress) ;
    }

    function setProtocolContracts(  address _nodeOperatorRegistry, address _nETHAddress, address _oracleAddress, address _validatorNftAddress ) external onlyOwner {
        _setProtocolContracts(_nodeOperatorRegistry, _nETHAddress, _oracleAddress, _validatorNftAddress); 
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function stakeETH(address _referral, uint256 _node_operator) external payable nonReentrant {
        require(msg.value != 0, "Stake amount must not be Zero");
        require(iNodeOperatorRegistry.isTrustedOperator(_node_operator) == true, "The message sender is not part of Trusted KingHash Operators");
        require(msg.value >= 100 wei, "Stake amount must be minimum  100 wei");
        require(_referral != address(0x0), "Referral address must be provided");

        uint256 depositNet;
        if (getDepositFeeRate() == 0) {
            depositNet = msg.value;
        }
        else {
            depositNet = msg.value - (getDepositFeeRate() / totalBasisPoints * msg.value);
        }
        addBufferedEtherPosition(depositNet);
        addToOperatorBalance(_node_operator, depositNet);
        iNETH.mint(depositNet, msg.sender);

        emit DepositReceived(msg.sender, msg.value, _referral);
    }


    //    function eth32Route(bytes calldata data) internal returns (bool) {
    //     bytes32 hash = precheck(data);
    //     signercheck(bytes32(data[256:288]), bytes32(data[288:320]), uint8(bytes1(data[1])), hash, vault.authority());
    //     deposit(data);
    //     vault.settle(); // we can optimize this to settle only a particular vault
    //     //nftContract.whiteListMint(data[16:64], msg.sender);
    //     return true;
    // }


    //  function unstake()nonReentrant whenNotPaused {}

    /*  function wrapNFT(){
        checkWrapNftIsValid  from VNFT
        checkTransferredkETH from ERC20
        verifyNFTValue  from VNFT
        addUserGasHeight from EexceutionVault
        burnNETH  from NETH
        transferNFT
    } */

    /*  function unwrapNFT(){
            require(iNodeOperatorRegistry.isTrustedOperator(_node_operator) == true , "The message sender is not part of Trusted KingHash Operators");
            verifyNFTValue from Oracle
            transferFromNFT from VNFT
            removeUserGasHeight from EexceutionVault
            mintNETH from NETH
    }*/

    /*   function unstakeNFT(){
        // require(iNodeOperatorRegistry.getNodeOperator(_node_operator) == true , "The message sender is not part of KingHash Operators");
        // check caller nft , trasnfer this nft to protocoo ,check nodeOperatorRanking, take down validator
    }*/


    function handleOracleReport(uint64 _beaconBalance, uint32 _beaconValidators) external override {
        require(msg.sender == oracleAddress , "The msg.sender is not from BeaconOracle");
       
        uint256 depositedValidators = iVNFT.activeValidators().length ;
        require(_beaconValidators <= depositedValidators, "More Validators than Reported ");
        require(_beaconValidators >= totalBeaconValidators, "Less Validators than Reported ");

        // Save the current _beaconBalance, transientBalance , _beaconValidators  
        setBeaconEtherPosition(_beaconBalance) ;
        uint256 appearedValidators = _beaconValidators- totalBeaconValidators;
        uint256 transientEther = appearedValidators * 32 ether;
        setTransientEtherPosition(transientEther);
        setTotalBeaconValidators(depositedValidators);
        //check for EL Rewards
        // uint256 executionLayerRewards =  computeELRewards() ;

    }


    function getTotalPooledEther() external view override returns (uint256){
        return bufferedEtherPosition + transientEtherPosition + beaconEtherPosition;
    }

    function getChainUpFromNodeRegistry() internal pure returns (uint256) {
        return 1;
    }

    function addBufferedEtherPosition(uint256 _amt) internal {
        bufferedEtherPosition += _amt;
    }

    function setTotalBeaconValidators(uint256 _beaconValidators) internal {
        totalBeaconValidators = _beaconValidators;
    }

    function subtractBufferedEtherPosition(uint256 _amt) internal {
        bufferedEtherPosition -= _amt;
    }

    function setTransientEtherPosition(uint256 _amt) internal {
        transientEtherPosition = _amt;
    }

    function setBeaconEtherPosition(uint256 _amt) internal {
        beaconEtherPosition = _amt;
    }

    function setDepositFeeRate(uint256 _rate) external onlyOwner {
        depositFeeRate = _rate;
    }

    function getDepositFeeRate() internal view returns (uint256) {
        return depositFeeRate;
    }

    function addToOperatorBalance(uint256 operator, uint256 amount) internal {
        // require(iNodeOperatorRegistry.checkTrustOperator(_node_operator) == true , "The message sender is not part of KingHash Operators");
        operatorPoolBalances[operator] += amount;
    }

    function checkOperatorBalance(uint256 operator) external view returns (uint256)  {
        return operatorPoolBalances[operator];
    }

    function computeWithdrawableEther() external view returns (uint256){
        //  consider EL rewards, Buffered/Deposited Ether
        return bufferedEtherPosition + computeELRewards();
    }

    function computeELRewards() internal pure returns (uint256) {
        return 0;
    }


}
