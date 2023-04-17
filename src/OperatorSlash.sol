// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "src/interfaces/IVNFT.sol";
import "src/interfaces/ILiquidStaking.sol";
import "src/interfaces/INodeOperatorsRegistry.sol";
import "src/interfaces/IWithdrawalRequest.sol";
import "src/interfaces/IOperatorSlash.sol";

contract OperatorSlash is
    IOperatorSlash,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    ILiquidStaking public liquidStakingContract;
    IVNFT public vNFTContract;
    INodeOperatorsRegistry public nodeOperatorRegistryContract;
    IWithdrawalRequest public withdrawalRequestContract;
    address public vaultManagerContractAddress;
    address public dao;

    // When nft is punished by the network,
    //   for the user's nft, the penalty amount should be given to the user
    // When the operator margin is insufficient, how much compensation is owed will be recorded
    // key is tokenId, value is nft compensated
    mapping(uint256 => uint256) public nftWillCompensated;
    // Compensation already paid
    mapping(uint256 => uint256) public nftHasCompensated;
    // Record the set of tokenids that the operator will compensate
    mapping(uint256 => uint256[]) public operatorSlashArrears;
    // The index of the compensation that has been completed is used for the distribution of compensation when replenishing the margin
    uint256 public operatorCompensatedIndex;

    // delay exit slash
    // When the operator does not nft unstake or large withdrawals for more than 72 hours, the oracle will be punished
    uint256 public delayedExitSlashStandard;
    // Penalty amount for each validator per block
    uint256 public slashAmountPerBlockPerValidator;

    // Record the latest penalty information
    // key is tokenId, value is blockNumber
    mapping(uint256 => uint256) public nftExitDelayedSlashRecords;
    // key is requestId, value is blockNumber
    mapping(uint256 => uint256) public largeExitDelayedSlashRecords;

    error PermissionDenied();
    error InvalidParameter();
    error NoSlashNeeded();
    error ExcessivePenaltyAmount();

    modifier onlyLiquidStaking() {
        if (address(liquidStakingContract) != msg.sender) revert PermissionDenied();
        _;
    }

    modifier onlyVaultManager() {
        if (msg.sender != vaultManagerContractAddress) revert PermissionDenied();
        _;
    }

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address _dao,
        address _liquidStakingAddress,
        address _nVNFTContractAddress,
        address _nodeOperatorRegistryAddress,
        address _withdrawalRequestContractAddress,
        address _vaultManagerContractAddress,
        // goerli 7200; mainnet 50400;
        uint256 _delayedExitSlashStandard
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        liquidStakingContract = ILiquidStaking(_liquidStakingAddress);
        vNFTContract = IVNFT(_nVNFTContractAddress);
        nodeOperatorRegistryContract = INodeOperatorsRegistry(_nodeOperatorRegistryAddress);
        withdrawalRequestContract = IWithdrawalRequest(_withdrawalRequestContractAddress);
        vaultManagerContractAddress = _vaultManagerContractAddress;
        dao = _dao;

        delayedExitSlashStandard = _delayedExitSlashStandard;

        // 2000000000000 * 7200 * 365 = 5256000000000000000 = 5.256 eth
        slashAmountPerBlockPerValidator = 2000000000000;
    }

    /**
     * @notice According to the report results of the oracle machine, the operator who has reduced nft will be punished
     * @param _exitTokenIds token id
     * @param _amounts slash amounts
     */
    function slashOperator(uint256[] memory _exitTokenIds, uint256[] memory _amounts) external onlyVaultManager {
        if (_exitTokenIds.length != _amounts.length || _amounts.length == 0) revert InvalidParameter();
        nodeOperatorRegistryContract.slash(_exitTokenIds, _amounts);
    }

    /**
     * @notice According to the report result of the oracle machine, punish the operator who fails to exit in time
     * @param _nftExitDelayedTokenIds exit delayed tokenIds
     * @param _largeExitDelayedRequestIds large exit delayed requestIds
     */
    function slashOfExitDelayed(uint256[] memory _nftExitDelayedTokenIds, uint256[] memory _largeExitDelayedRequestIds)
        external
        onlyVaultManager
    {
        uint256[] memory nftExitHeight = vNFTContract.getNftExitBlockNumbers(_nftExitDelayedTokenIds);

        for (uint256 i = 0; i < _nftExitDelayedTokenIds.length; ++i) {
            uint256 tokenId = _nftExitDelayedTokenIds[i];
            uint256 startNumber = withdrawalRequestContract.getNftUnstakeBlockNumber(tokenId);
            if (startNumber == 0) revert InvalidParameter();
            if (nftExitDelayedSlashRecords[tokenId] != 0) {
                startNumber = nftExitDelayedSlashRecords[tokenId];
            }

            nftExitDelayedSlashRecords[tokenId] = block.number;
            uint256 operatorId = vNFTContract.operatorOf(tokenId);

            _delaySlash(operatorId, startNumber, nftExitHeight[i] == 0 ? block.number : nftExitHeight[i], 1);
        }

        for (uint256 i = 0; i < _largeExitDelayedRequestIds.length; ++i) {
            uint256 requestId = _largeExitDelayedRequestIds[i];
            uint256 operatorId = 0;
            uint256 withdrawHeight = 0;
            uint256 claimEthAmount = 0;
            (operatorId, withdrawHeight,,, claimEthAmount,,) =
                withdrawalRequestContract.getWithdrawalOfRequestId(requestId);
            uint256 startNumber = withdrawHeight;
            if (largeExitDelayedSlashRecords[requestId] != 0) {
                startNumber = largeExitDelayedSlashRecords[requestId];
            }
            largeExitDelayedSlashRecords[requestId] = block.number;

            _delaySlash(operatorId, startNumber, block.number, (claimEthAmount - claimEthAmount % 32 ether) / 32 ether);
        }
    }

    function _delaySlash(uint256 _operatorId, uint256 _startNumber, uint256 _endNumber, uint256 validatorNumber)
        internal
    {
        uint256 slashNumber = _endNumber - _startNumber;
        if (slashNumber < delayedExitSlashStandard) revert NoSlashNeeded();
        uint256 _amount = slashNumber * slashAmountPerBlockPerValidator * validatorNumber;
        nodeOperatorRegistryContract.slashOfExitDelayed(_operatorId, _amount);
    }

    /**
     * @notice Receive slash fund, Because the operator may have insufficient margin, _slashAmounts may be less than or equal to _requireAmounts
     * @param _exitTokenIds exit tokenIds
     * @param _slashAmounts slash amount
     * @param _requireAmounts require slas amount
     */
    function slashReceive(
        uint256[] memory _exitTokenIds,
        uint256[] memory _slashAmounts,
        uint256[] memory _requireAmounts
    ) external payable {
        if (msg.sender != address(nodeOperatorRegistryContract)) revert PermissionDenied();
        for (uint256 i = 0; i < _exitTokenIds.length; ++i) {
            uint256 tokenId = _exitTokenIds[i];
            uint256 operatorId = vNFTContract.operatorOf(tokenId);
            if (vNFTContract.ownerOf(tokenId) == address(liquidStakingContract)) {
                liquidStakingContract.addPenaltyFundToStakePool{value: _slashAmounts[i]}(operatorId, _slashAmounts[i]);
            } else {
                uint256 requirAmount = _requireAmounts[i];
                uint256 slashAmount = _slashAmounts[i];
                if (requirAmount < slashAmount) revert InvalidParameter();
                if (requirAmount != slashAmount) {
                    nftWillCompensated[tokenId] += requirAmount - slashAmount;
                    operatorSlashArrears[operatorId].push(tokenId);
                }
                nftHasCompensated[tokenId] += slashAmount;
            }

            emit SlashReceive(operatorId, tokenId, _slashAmounts[i], _requireAmounts[i]);
        }
    }

    /**
     * @notice The receiving function of the penalty, used for the automatic transfer after the operator recharges the margin
     * @param _operatorId operator Id
     * @param _amount slash amount
     */
    function slashArrearsReceive(uint256 _operatorId, uint256 _amount) external payable {
        emit ArrearsReceiveOfSlash(_operatorId, _amount);

        if (msg.sender != address(nodeOperatorRegistryContract)) revert PermissionDenied();
        uint256 compensatedIndex = operatorCompensatedIndex;
        while (
            operatorSlashArrears[_operatorId].length != 0
                && operatorSlashArrears[_operatorId].length - 1 >= compensatedIndex
        ) {
            uint256 tokenId = operatorSlashArrears[_operatorId][compensatedIndex];
            uint256 arrears = nftWillCompensated[tokenId];
            if (_amount >= arrears) {
                nftWillCompensated[tokenId] = 0;
                nftHasCompensated[tokenId] += arrears;
                compensatedIndex += 1;
                _amount -= arrears;
            } else {
                nftWillCompensated[tokenId] -= _amount;
                nftHasCompensated[tokenId] += _amount;
                _amount = 0;
            }

            if (_amount == 0) {
                break;
            }
        }

        if (compensatedIndex != 0 && compensatedIndex != operatorCompensatedIndex) {
            operatorCompensatedIndex = compensatedIndex;
        }

        if (_amount != 0) {
            liquidStakingContract.addPenaltyFundToStakePool{value: _amount}(_operatorId, _amount);
        }
    }

    /**
     * @notice claim compensation
     * @param _tokenIds tokens Id
     * @param _owner owner address
     */
    function claimCompensated(uint256[] memory _tokenIds, address _owner) external onlyVaultManager returns (uint256) {
        uint256 totalCompensated;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            if (nftHasCompensated[tokenId] != 0) {
                totalCompensated += nftHasCompensated[tokenId];
                nftHasCompensated[tokenId] = 0;
            }
        }
        if (totalCompensated != 0) {
            payable(_owner).transfer(totalCompensated);
        }

        emit CompensatedClaimed(_owner, totalCompensated);
        return totalCompensated;
    }

    /**
     * @notice Set the penalty amount per block per validator
     * @param _slashAmountPerBlockPerValidator unit penalty amount
     */
    function setSlashAmountPerBlockPerValidator(uint256 _slashAmountPerBlockPerValidator) external onlyOwner {
        if (_slashAmountPerBlockPerValidator > 10000000000000) revert ExcessivePenaltyAmount();
        emit SlashAmountPerBlockPerValidatorSet(slashAmountPerBlockPerValidator, _slashAmountPerBlockPerValidator);
        slashAmountPerBlockPerValidator = _slashAmountPerBlockPerValidator;
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
     * @notice Set new withdrawalRequestContract address
     * @param _withdrawalRequestContractAddress new withdrawalRequestContract address
     */
    function setWithdrawalRequestContract(address _withdrawalRequestContractAddress) external onlyDao {
        emit WithdrawalRequestContractSet(address(withdrawalRequestContract), _withdrawalRequestContractAddress);
        withdrawalRequestContract = IWithdrawalRequest(_withdrawalRequestContractAddress);
    }

    /**
     * @notice Set new vaultManagerContractA address
     * @param _vaultManagerContract new vaultManagerContract address
     */
    function setVaultManagerContract(address _vaultManagerContract) external onlyDao {
        emit VaultManagerContractSet(vaultManagerContractAddress, _vaultManagerContract);
        vaultManagerContractAddress = _vaultManagerContract;
    }

    /**
     * @notice Set proxy address of LiquidStaking
     * @param _liquidStakingContractAddress proxy address of LiquidStaking
     * @dev will only allow call of function by the address registered as the owner
     */
    function setLiquidStaking(address _liquidStakingContractAddress) external onlyDao {
        emit LiquidStakingChanged(address(liquidStakingContract), _liquidStakingContractAddress);
        liquidStakingContract = ILiquidStaking(_liquidStakingContractAddress);
    }

    /**
     * @notice set dao address
     * @param _dao new dao address
     */
    function setDaoAddress(address _dao) external onlyOwner {
        if (_dao == address(0)) revert InvalidParameter();
        emit DaoAddressChanged(dao, _dao);
        dao = _dao;
    }
}
