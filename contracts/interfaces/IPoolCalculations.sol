// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolCalculations {
    function depositIdToDepositor(
        bytes32 _depositId
    ) external view returns (address);

    function depositIdToDepositAmount(
        bytes32 _depositId
    ) external view returns (uint256);

    function depositIdToTokensMinted(
        bytes32 _depositId
    ) external view returns (bool);

    function withdrawIdToDepositor(
        bytes32 _withdrawId
    ) external view returns (address);

    function withdrawIdToDepositAmount(
        bytes32 _withdrawId
    ) external view returns (uint256);

    function createWithdrawOrder(
        uint256 _amount,
        uint256 _poolNonce,
        address _poolToken,
        address _sender
    ) external returns (bytes memory);

    function getWithdrawOrderFulfillment(
        bytes32 withdrawId,
        uint256 totalAvailableForUser,
        uint256 amount,
        address _poolToken
    ) external view returns (address depositor, uint256 poolTokensToBurn);

    function createDepositOrder(
        address _sender,
        uint256 _amount
    ) external returns (bytes32 depositId);

    function calculatePoolTokensToMint(
        bytes32 _depositId,
        uint256 _poolPositionAmount,
        uint256 _poolTokenSupply
    ) external returns (uint256, address);
}
