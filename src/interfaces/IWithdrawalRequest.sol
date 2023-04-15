// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.8;

/**
 * @title Interface for WithdrawalRequest
 * @notice WithdrawalRequest contract
 */
interface IWithdrawalRequest {
    function getNftUnstakeBlockNumber(uint256 _tokenId) external view returns (uint256);
    function getWithdrawalOfRequestId(uint256 _requestId)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, address, bool);
    function getOperatorLargeWitdrawalPendingInfo(uint256 _operatorId) external view returns (uint256, uint256);
    function receiveWithdrawals(uint256 _operatorId, uint256 _amount) external payable;
}
