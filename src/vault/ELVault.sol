// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/interfaces/ILiquidStaking.sol";

/**
 * @title ELVault for managing rewards
 */
contract ELVault is ReentrancyGuard, Initializable {
    address public liquidStakingContractAddress;
    address public dao;
    uint256 public operatorId;

    event DaoAddressChanged(address _oldDao, address _dao);
    event LiquidStakingChanged(address _from, address _to);
    event Transferred(address _to, uint256 _amount);
    event RewardReinvestment(address _liquidStakingContract, uint256 _rewards);

    error PermissionDenied();
    error InvalidAddr();

    modifier onlyLiquidStaking() {
        if (liquidStakingContractAddress != msg.sender) revert PermissionDenied();
        _;
    }

    modifier onlyDao() {
        if (msg.sender != dao) revert PermissionDenied();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    /**
     * @notice Initializes the NodeCapitalVault contract by setting the required external contracts ,
     * ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable and `_aggregatorProxyAddress`
     * @dev initializer - A modifier that defines a protected initializer function that can be invoked at most once
     * @param _dao dao address
     * @param _liquidStakingProxyAddress liquidStaking Address
     * @param _operatorId operator Id
     */
    function initialize(address _dao, address _liquidStakingProxyAddress, uint256 _operatorId) public initializer {
        dao = _dao;
        liquidStakingContractAddress = _liquidStakingProxyAddress;
        operatorId = _operatorId;
    }

    /**
     * @notice transfer ETH
     * @param _amount transfer amount
     * @param _to transfer to address
     */
    function transfer(uint256 _amount, address _to) external nonReentrant onlyLiquidStaking {
        if (_to == address(0)) revert InvalidAddr();

        payable(_to).transfer(_amount);
        emit Transferred(_to, _amount);
    }

    /**
     * @notice transfer ETH
     * @param _amount transfer amount
     */
    function reinvestment(uint256 _amount) external nonReentrant onlyLiquidStaking {
        ILiquidStaking(liquidStakingContractAddress).receiveRewards{value: _amount}(_amount);
        emit RewardReinvestment(liquidStakingContractAddress, _amount);
    }

    /**
     * @notice Set proxy address of LiquidStaking
     * @param _liquidStakingContractAddress proxy address of LiquidStaking
     * @dev will only allow call of function by the address registered as the owner
     */
    function setLiquidStaking(address _liquidStakingContractAddress) external onlyDao {
        if (_liquidStakingContractAddress == address(0)) revert InvalidAddr();
        emit LiquidStakingChanged(liquidStakingContractAddress, _liquidStakingContractAddress);
        liquidStakingContractAddress = _liquidStakingContractAddress;
    }

    /**
     * @notice set dao address
     * @param _dao new dao address
     */
    function setDaoAddress(address _dao) external onlyDao {
        if (_dao == address(0)) revert InvalidAddr();
        emit DaoAddressChanged(dao, _dao);
        dao = _dao;
    }

    receive() external payable {}
}
