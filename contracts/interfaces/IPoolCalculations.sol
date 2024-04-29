// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolCalculations {
    function poolNonce(address) external view returns (uint256);

    function depositIdToDepositor(bytes32) external view returns (address);

    function depositIdToDepositAmount(bytes32) external view returns (uint256);

    function depositIdToTokensMinted(bytes32) external view returns (bool);

    function withdrawIdToDepositor(bytes32) external view returns (address);

    function withdrawIdToDepositAmount(bytes32) external view returns (uint256);

    function createWithdrawOrder(
        uint256,
        address,
        address
    ) external returns (bytes memory);

    function fulfillWithdrawOrder(
        bytes32,
        uint256,
        uint256,
        uint256,
        address
    ) external returns (address, uint256);

    function undoPositionInitializer(bytes32) external returns (address);

    function undoDeposit(bytes32) external returns (address);

    function undoPivot(uint256, uint256) external;

    function clearPivotTarget() external;

    function createDepositOrder(
        address,
        address,
        uint256
    ) external returns (bytes32, uint256);

    function updateDepositReceived(
        bytes32,
        uint256,
        uint256
    ) external returns (address);

    function depositIdMinted(bytes32) external;

    function openSetPosition(string memory, string memory, uint256) external;

    function getReceivingChain() external view returns (uint256);
    function getCurrentPositionData(
        address
    ) external view returns (string memory, string memory);
    function targetPositionChain(address) external view returns (uint256);

    function createPivotExitMessage(
        address
    ) external view returns (bytes memory);
    function pivotCompleted(
        address,
        uint256,
        uint256
    ) external returns (uint256);
    function calculatePoolTokensToMint(
        bytes32,
        uint256
    ) external view returns (uint256, address);
}
