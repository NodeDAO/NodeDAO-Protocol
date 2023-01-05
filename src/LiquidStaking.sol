// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LiquidStaking is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    
    bytes private withdrawalCredentials;
    uint256 private totalBeaconValidators ;
    bytes32 private nodeRankingCommitment ;
    uint256 public constant depositSize = 32 ether;
    uint256 private bufferedEtherPosition ;
    uint256 private depositFeeRate ;
    uint256 public constant totalBasisPoints = 10000;

    mapping(address => uint256) public operatorPoolBalances;


    event DepositReceived(address indexed from, uint256 amount, address indexed _referral);
    event ELRewardsReceived(uint256 balance);
    event EtherDeposited(address from, uint256 balance, uint256 height);

    // function initialize( bytes memory withdrawalCreds, address _validatorNftAddress , address _nETHAddress, address _nodeOperatorRegistry  ) external initializer {
    function initialize( bytes memory withdrawalCreds ) external initializer {
        __Ownable_init(); 
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        withdrawalCredentials = withdrawalCreds;
        // IVNFT vnft = IVNFT(_validatorNftAddress) ;
        // INETH iNETH = INETH(_nETHAddress) ;
        // INodeOperatorRegistry iNETH =        
         // INodeOperatorRegistry iNodeOperatorRegistry = INETH(_nodeOperatorRegistry) ;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function stakeETH(address _referral, address _node_operator) external payable nonReentrant {
        require(msg.value != 0, "Stake amount must not be Zero");
        require(msg.value >= 100 wei, "Stake amount must be minimum  100 wei");
        require(_referral != address(0x0), "Referral address must be provided");

        if (_node_operator == address(0)) {
            _node_operator = getChainUp();
        }

        // require(iNodeOperatorRegistry.checkTrustOperator(_node_operator) == true , "The message sender is not part of KingHash Operators");

        uint256 depositNet ;
        if(getDepositFeeRate() == 0 ){
            depositNet = msg.value;
        }
        else {         
            depositNet = getDepositFeeRate() / totalBasisPoints * msg.value ;
        }
        addBufferedEtherPosition(depositNet) ;
        addToOperatorBalance(_node_operator, depositNet);
        // iNETH.mintKETH(msg.sender, depositNet);

        emit DepositReceived(msg.sender, msg.value, _referral);
    }

    function getChainUp() internal pure returns(address) {
         return  address(0) ;
    }

    function addBufferedEtherPosition(uint256 _amt) internal {
        bufferedEtherPosition += _amt ;
    }

    function setDepositFeeRate(uint256 _rate) external onlyOwner {
        depositFeeRate = _rate ;
    }

    function getDepositFeeRate() internal view returns(uint256) {
        return depositFeeRate ;
    }
    
    function addToOperatorBalance(address operator, uint256 amount) internal {
        // require(iNodeOperatorRegistry.checkTrustOperator(_node_operator) == true , "The message sender is not part of KingHash Operators");
        operatorPoolBalances[operator] += amount;
    }

}
