// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/interfaces/ISSVNetwork.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract SSVManager is ReentrancyGuard, Initializable {
    address public ssvRouter;
    ISSVNetwork public ssvNetwork;
    IERC20 public ssvToken;

    error PermissionDenied();

    modifier onlySSVRouter() {
        if (msg.sender != ssvRouter) revert PermissionDenied();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(address _ssvRouter, address _ssvNetwork, address _ssvToken) public initializer {
        ssvNetwork = ISSVNetwork(_ssvNetwork);
        ssvToken = IERC20(_ssvToken);
        ssvRouter = _ssvRouter;
    }

    /// @notice Registers a new validator on the SSV Network
    function registerValidator(
        bytes calldata publicKey,
        uint64[] memory operatorIds,
        bytes calldata sharesData,
        uint256 amount,
        ISSVNetworkCore.Cluster memory cluster
    ) external onlySSVRouter {
        ssvNetwork.registerValidator(publicKey, operatorIds, sharesData, amount, cluster);
    }

    /// @notice Removes an existing validator from the SSV Network
    function removeValidator(
        bytes calldata publicKey,
        uint64[] memory operatorIds,
        ISSVNetworkCore.Cluster memory cluster
    ) external onlySSVRouter {
        ssvNetwork.removeValidator(publicKey, operatorIds, cluster);
    }

    /// @notice Reactivates a cluster
    function reactivate(uint64[] memory operatorIds, uint256 amount, ISSVNetworkCore.Cluster memory cluster)
        external
        onlySSVRouter
    {
        ssvNetwork.reactivate(operatorIds, amount, cluster);
    }

    /// @notice Deposits tokens into a cluster
    function deposit(address owner, uint64[] memory operatorIds, uint256 amount, ISSVNetworkCore.Cluster memory cluster)
        external
        onlySSVRouter
    {
        ssvNetwork.deposit(owner, operatorIds, amount, cluster);
    }

    /// @notice Withdraws tokens from a cluster
    function withdraw(uint64[] memory operatorIds, uint256 tokenAmount, ISSVNetworkCore.Cluster memory cluster)
        external
        onlySSVRouter
    {
        ssvNetwork.withdraw(operatorIds, tokenAmount, cluster);
    }

    /// @notice set ssv validator fee recipient address
    function setFeeRecipientAddress(address recipientAddress) external onlySSVRouter {
        ssvNetwork.setFeeRecipientAddress(recipientAddress);
    }

    /// @notice transfer ssv token
    function transfer(address to, uint256 amount) external onlySSVRouter returns (bool) {
        return ssvToken.transfer(to, amount);
    }

    /// @notice approve ssv token
    function approve(address spender, uint256 amount) external onlySSVRouter returns (bool) {
        return ssvToken.approve(spender, amount);
    }
}
