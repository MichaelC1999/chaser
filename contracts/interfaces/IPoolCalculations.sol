// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolCalculations {
    function protocolFeePct() external view returns (uint256);

    function depositIdToDepositor(bytes32) external view returns (address);
    function depositIdToDepositAmount(bytes32) external view returns (uint256);
    function depositIdToDepoNonce(bytes32) external view returns (uint256);
    function depositIdToTokensMinted(bytes32) external view returns (bool);

    function withdrawIdToDepositor(bytes32) external view returns (address);
    function withdrawIdToAmount(bytes32) external view returns (uint256);
    function withdrawIdToOutputAmount(bytes32) external view returns (uint256);
    function withdrawIdToUserPoolTokens(
        bytes32
    ) external view returns (uint256);
    function withdrawIdToWithNonce(bytes32) external view returns (uint256);
    function withdrawIdToTokensBurned(bytes32) external view returns (bool);

    function poolToPendingDeposits(address) external view returns (uint256);
    function poolToPendingWithdraws(address) external view returns (uint256);
    function poolToTimeout(address) external view returns (uint256);
    function poolToRescueChain(address) external view returns (uint256);

    function poolDepositOpenedNonce(address) external view returns (uint256);
    function poolDepositFinishedNonce(address) external view returns (uint256);
    function poolWithdrawNonce(address) external view returns (uint256);
    function poolPivotNonce(address) external view returns (uint256);
    function poolToPivotPending(address) external view returns (bool);

    function targetPositionMarketId(
        address
    ) external view returns (bytes memory);
    function targetPositionChain(address) external view returns (uint256);
    function targetPositionProtocolHash(
        address
    ) external view returns (bytes32);
    function targetPositionProtocol(
        address
    ) external view returns (string memory);

    function currentPositionAddress(address) external view returns (address);
    function currentPositionMarketId(
        address
    ) external view returns (bytes memory);
    function currentPositionProtocolHash(
        address
    ) external view returns (bytes32);
    function currentPositionProtocol(
        address
    ) external view returns (string memory);
    function currentRecordPositionValue(
        address
    ) external view returns (uint256);
    function currentPositionValueTimestamp(
        address
    ) external view returns (uint256);

    function poolToUserWithdrawTimeout(
        address,
        address
    ) external view returns (uint256);

    function setProtocolFeePct(uint256) external;

    function createWithdrawOrder(
        uint256,
        address,
        address,
        bytes32
    ) external returns (bytes memory);

    function fulfillWithdrawOrder(
        bytes32,
        uint256,
        uint256
    ) external returns (address, uint256);

    function setWithdrawReceived(bytes32, uint256) external returns (address);

    function openSetPosition(
        bytes memory,
        string memory,
        uint256
    ) external returns (address);

    function createDepositOrder(
        address,
        address,
        uint256,
        bytes32
    ) external returns (bytes32, uint256, uint256);

    function updateDepositReceived(bytes32, uint256, uint256) external;

    function pivotCompleted(address, uint256) external;

    function getCurrentPositionData(
        address
    ) external view returns (string memory, bytes memory, bool, bool);

    function checkTimestamp(
        address
    ) external view returns (uint256, bool, uint256);

    function checkPivotBlock(address) external view returns (bool);

    function createInitialSetPositionMessage(
        bytes32,
        address
    ) external view returns (bytes memory);

    function createPivotExitMessage(
        address,
        uint256,
        address
    ) external view returns (bytes memory);

    function getMarketAddressFromId(
        bytes memory,
        bytes32
    ) external view returns (address);

    function calculatePoolTokensToMint(
        bytes32,
        address,
        address
    ) external view returns (uint256, address);

    function getScaledRatio(address, address) external view returns (uint256);

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
