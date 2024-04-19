// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolCalculations {
    function depositIdToDepositor(bytes32) external view returns (address);

    function depositIdToDepositAmount(bytes32) external view returns (uint256);

    function depositIdToTokensMinted(bytes32) external view returns (bool);

    function withdrawIdToDepositor(bytes32) external view returns (address);

    function withdrawIdToDepositAmount(bytes32) external view returns (uint256);

    function createWithdrawOrder(
        uint256,
        uint256,
        address,
        address
    ) external returns (bytes memory);

    function getWithdrawOrderFulfillment(
        bytes32,
        uint256,
        uint256,
        address
    ) external view returns (address, uint256);

    function createDepositOrder(address, uint256) external returns (bytes32);

    function updateDepositReceived(bytes32, uint256) external returns (address);

    function depositIdMinted(bytes32) external;

    function createPivotExitMessage(
        bytes32,
        string memory,
        uint256,
        address
    ) external view returns (bytes memory);

    function calculatePoolTokensToMint(
        bytes32,
        uint256,
        uint256
    ) external view returns (uint256, address);
}
