// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";

import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/ILiquidStaking.sol";

contract LiquidStaking is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable, ILiquidStaking{
    
    bytes private withdrawalCredentials;
    uint256 private totalBeaconValidators ;
    bytes32 private nodeRankingCommitment ;
    uint256 public constant depositSize = 32 ether;
    uint256 private depositFeeRate ;
    uint256 public constant totalBasisPoints = 10000;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 private bufferedEtherPosition ;
    uint256 private transientEtherPosition ;
    uint256 private beaconEtherPosition ;

    mapping(uint256 => uint256) public operatorPoolBalances;

    event DepositReceived(address indexed from, uint256 amount, address indexed _referral);
    event ELRewardsReceived(uint256 balance);
    event EtherDeposited(address from, uint256 balance, uint256 height);

    INodeOperatorsRegistry iNodeOperatorRegistry;
    // function initialize( bytes memory withdrawalCreds, address _validatorNftAddress , address _nETHAddress, address _nodeOperatorRegistry  ) external initializer {
    function initialize( bytes memory withdrawalCreds, address _nodeOperatorRegistry ) external initializer {
        __Ownable_init(); 
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        withdrawalCredentials = withdrawalCreds;
        iNodeOperatorRegistry = INodeOperatorsRegistry(_nodeOperatorRegistry) ;
        // IVNFT vnft = IVNFT(_validatorNftAddress) ;
        // INETH iNETH = INETH(_nETHAddress) ;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function stakeETH(address _referral, uint256 _node_operator) external payable nonReentrant {
        
        require(iNodeOperatorRegistry.isTrustedOperator(_node_operator) == true , "The message sender is not part of Trusted KingHash Operators");
        require(msg.value != 0, "Stake amount must not be Zero");
        require(msg.value >= 100 wei, "Stake amount must be minimum  100 wei");
        require(_referral != address(0x0), "Referral address must be provided") ;

        uint256 depositNet ;
        if(getDepositFeeRate() == 0 ){
            depositNet = msg.value;
        }
        else {         
            depositNet = getDepositFeeRate() / totalBasisPoints * msg.value ;
        }
        addBufferedEtherPosition(depositNet) ;
        addToOperatorBalance(_node_operator, depositNet);
        // iNETH.mint(msg.sender, depositNet);

        emit DepositReceived(msg.sender, msg.value, _referral);
    }

    function mintNFT(bytes calldata data) external payable nonReentrant {
        require(msg.value >= DEPOSIT_SIZE , "Stake amount must be minimum 32 ether");
        // require(iNodeOperatorRegistry.checkOperator(_node_operator) == true , "The message sender is not part of KingHash Operators");
        // eth32Route();
     }

    //  function unstake()nonReentrant whenNotPaused {}

    /*  function wrapNFT(){
        checkWrapNftIsValid
        checkTransferredkETH
        verifyNFTValue
        addUserGasHeight
        burnKETH
        transferNFT
    } */ 

    /*  function unwrapNFT(){
            require(iNodeOperatorRegistry.isTrustedOperator(_node_operator) == true , "The message sender is not part of Trusted KingHash Operators");
            verifyNFTValue from Oracle
            transferFromNFT from VNFT
            removeUserGasHeight from EexceutionVault
            mintKETH from NETH
    }*/ 

    //  function burnNFT(){}


    function handleOracleReport(uint256 data, bytes32 nodeRankingCommitment) external override{
       
    }
    


    function getTotalPooledEther() external override returns(uint256){
        return bufferedEtherPosition + transientEtherPosition + beaconEtherPosition ; 
    }

    function getChainUpFromNodeRegistry() internal pure returns(uint256) {
         return  1 ;
    }

    function addBufferedEtherPosition(uint256 _amt) internal {
        bufferedEtherPosition += _amt ;
    }

    function subtractBufferedEtherPosition(uint256 _amt) internal {
        bufferedEtherPosition -= _amt ;
    }

    function addTransientEtherPosition(uint256 _amt) internal {
        transientEtherPosition += _amt ;
    }

    function subtractTransientEtherPosition(uint256 _amt) internal {
        transientEtherPosition -= _amt ;
    }

    function addBeaconEtherPosition(uint256 _amt) internal {
        beaconEtherPosition += _amt ;
    }

    function subtractBeaconEtherPosition(uint256 _amt) internal {
        beaconEtherPosition -= _amt ;
    }

    function setDepositFeeRate(uint256 _rate) external onlyOwner {
        depositFeeRate = _rate ;
    }

    function getDepositFeeRate() internal view returns(uint256) {
        return depositFeeRate ;
    }
    
    function addToOperatorBalance(uint256 operator, uint256 amount) internal {
        // require(iNodeOperatorRegistry.checkTrustOperator(_node_operator) == true , "The message sender is not part of KingHash Operators");
        operatorPoolBalances[operator] += amount;
    }

    /* function getFreeEther() returns(uint256){
    //  consider EL rewards, Buffered/Deposited Ether
    return bufferedEtherPosition +  computeELRewards() ;
    } */

    /* function computeELRewards() internal returns (uint256) {
          return 0;
      }*/


}
