// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolCalculations {
    function poolNonce(address) external view returns (uint256);

    function depositIdToDepositor(bytes32) external view returns (address);

    function depositIdToDepositAmount(bytes32) external view returns (uint256);

    function depositIdToTokensMinted(bytes32) external view returns (bool);

    function withdrawIdToDepositor(bytes32) external view returns (address);

    function withdrawIdToDepositAmount(bytes32) external view returns (uint256);

    function poolDepositNonce(address) external view returns (uint256);

    function poolWithdrawNonce(address) external view returns (uint256);

    function poolPivotNonce(address) external view returns (uint256);

    function poolToPendingDeposits(address) external view returns (uint256);

    function poolToPendingWithdraws(address) external view returns (uint256);

    function poolToPivotPending(address) external view returns (bool);

    function createWithdrawOrder(
        uint256,
        address,
        address,
        bytes32
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

    function undoPivot(uint256) external;

    function createDepositOrder(
        address,
        address,
        uint256,
        bytes32
    ) external returns (bytes32, uint256);

    function updateDepositReceived(bytes32, uint256, uint256) external;

    function depositIdMinted(bytes32) external;
    function openSetPosition(
        bytes memory,
        string memory,
        uint256
    ) external returns (address);

    function getReceivingChain() external view returns (uint256);
    function getCurrentPositionData(
        address
    ) external view returns (string memory, bytes memory, bool);
    function targetPositionChain(address) external view returns (uint256);
    function getPivotBond(address) external view returns (uint256);
    function createInitialSetPositionMessage(
        bytes32,
        address
    ) external view returns (bytes memory);
    function createPivotExitMessage(
        address,
        uint256
    ) external view returns (bytes memory);
    function pivotCompleted(address, uint256) external;
    function calculatePoolTokensToMint(
        bytes32,
        uint256
    ) external view returns (uint256, address);
    function readCurrentPositionData(
        address
    )
        external
        view
        returns (
            address,
            bytes32,
            uint256,
            uint256,
            string memory,
            bytes memory
        );
    function poolTransactionStatus(
        address
    ) external view returns (uint256, uint256, bool);
}
