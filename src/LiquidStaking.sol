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
    INEth iNETH;
    // function initialize( bytes memory withdrawalCreds, address _validatorNftAddress , address _nETHAddress, address _nodeOperatorRegistry  ) external initializer {
    function initialize( bytes memory withdrawalCreds, address _nodeOperatorRegistry, address _nETHAddress ) external initializer {
        __Ownable_init(); 
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        withdrawalCredentials = withdrawalCreds;
        iNodeOperatorRegistry = INodeOperatorsRegistry(_nodeOperatorRegistry) ;
        // IVNFT vnft = IVNFT(_validatorNftAddress) ;
         iNETH = INEth(_nETHAddress) ;
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


    function handleOracleReport(uint256 data, bytes32 nodeRankingCommitment) external override{
            //    require(msg.sender == getOracle(), "APP_AUTH_FAILED");
        // (uint256 _beaconBalance, uint256 _beaconValidators) = decode(data);
        // uint256 depositedValidators = DEPOSITED_VALIDATORS_POSITION.getStorageUint256();
        // require(_beaconValidators <= depositedValidators, "REPORTED_MORE_DEPOSITED");
        // uint256 beaconValidators = BEACON_VALIDATORS_POSITION.getStorageUint256();
        // require(_beaconValidators >= beaconValidators, "REPORTED_LESS_VALIDATORS");
        // uint256 appearedValidators = _beaconValidators.sub(beaconValidators);
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
