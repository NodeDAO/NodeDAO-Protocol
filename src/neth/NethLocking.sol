// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract NethLocking is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    address public dao;
    IERC20 public nethContract;

    struct LockingInfo {
        uint256 lockAmounts;
        uint256 settleBlock;
        uint256 credits;
    }

    mapping(address => LockingInfo) internal lockingInfos;

    event NethDeposited(address _sender, uint256 _amount, uint256 _lockAmounts, uint256 _settleBlock, uint256 _credits);
    event NethWithdraw(address _sender, uint256 _amount, uint256 _lockAmounts, uint256 _settleBlock, uint256 _credits);
    event DaoAddressChanged(address oldDao, address _dao);
    event NethContractAddressChanged(address _oldNethContractAddr, address _nethContractAddr);

    error PermissionDenied();
    error InvalidParameter();
    error NotSetNethContract();
    error TokenTransferFailed();
    error InsufficientBalance();

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address _dao) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _pause();
        dao = _dao;
    }

    function depositNeth(uint256 _amount) external nonReentrant whenNotPaused {
        _deposit(_amount);

        LockingInfo memory userInfo = lockingInfos[msg.sender];
        if (userInfo.settleBlock == 0) {
            lockingInfos[msg.sender] = LockingInfo({lockAmounts: _amount, settleBlock: block.number, credits: 0});
        }

        userInfo.credits += userInfo.lockAmounts * (block.number - userInfo.settleBlock);
        userInfo.lockAmounts += _amount;
        userInfo.settleBlock = block.number;

        lockingInfos[msg.sender] = userInfo;

        emit NethDeposited(msg.sender, _amount, userInfo.lockAmounts, userInfo.settleBlock, userInfo.credits);
    }

    function _deposit(uint256 _amount) internal {
        if (!nethContract.transferFrom(msg.sender, address(this), _amount)) {
            revert TokenTransferFailed();
        }
    }

    function withdrawNeth(uint256 _amount) external nonReentrant whenNotPaused {
        LockingInfo memory userInfo = lockingInfos[msg.sender];
        if (_amount > userInfo.lockAmounts) revert InsufficientBalance();
        userInfo.credits += userInfo.lockAmounts * (block.number - userInfo.settleBlock);
        userInfo.lockAmounts -= _amount;
        userInfo.settleBlock = block.number;

        lockingInfos[msg.sender] = userInfo;

        _withdraw(msg.sender, _amount);

        emit NethWithdraw(msg.sender, _amount, userInfo.lockAmounts, userInfo.settleBlock, userInfo.credits);
    }

    function _withdraw(address _to, uint256 _amount) internal {
        if (!nethContract.transfer(_to, _amount)) {
            revert TokenTransferFailed();
        }
    }

    function getUserLockingInfo(address _user) public view returns (uint256 _balance, uint256 _credits) {
        LockingInfo memory userInfo = lockingInfos[_user];
        _balance = userInfo.lockAmounts;
        _credits = userInfo.credits + userInfo.lockAmounts * (block.number - userInfo.settleBlock);

        return (_balance, _credits);
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

    /**
     * @notice set neth contract address
     * @param _nethContractAddr neth contract address
     */
    function setNethContractAddress(address _nethContractAddr) external onlyDao {
        if (_nethContractAddr == address(0)) revert InvalidParameter();
        emit NethContractAddressChanged(address(nethContract), _nethContractAddr);
        nethContract = IERC20(_nethContractAddr);
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
        if (address(nethContract) == address(0)) revert NotSetNethContract();
        _unpause();
    }
}
