// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgeLogic {
    function addConnections(address, address, address) external;
    function handlePositionInitializer(
        uint256,
        address,
        address,
        bytes32,
        address,
        address,
        bytes32
    ) external;
    function handleEnterPivot(
        address,
        uint256,
        address,
        bytes32,
        address
    ) external;
    function returnToPool(bytes4, address, address, bytes32, uint256) external;
    function handleUserDeposit(address, bytes32, uint256, uint256) external;

    function sendPositionBalance(address, bytes32, uint256) external;
    function executeExitPivot(address, bytes memory) external;
    function userWithdrawSequence(address, bytes memory) external;

    // Public state variable accessors
    function managerChainId() external view returns (uint256);
    function registry() external view returns (address);
    function messenger() external view returns (address);
    function bridgeReceiverAddress() external view returns (address);
    function integratorAddress() external view returns (address);
    function poolToCurrentPositionMarket(
        address
    ) external view returns (address);
    function poolToCurrentProtocolHash(address) external view returns (bytes32);
    function positionEntranceAmount(address) external view returns (uint256);
    function poolToAsset(address) external view returns (address);
    function userDepositNonce(bytes32) external view returns (uint256);
    function userCumulativeDeposits(bytes32) external view returns (uint256);
    function nonceToPositionValue(bytes32) external view returns (uint256);
    function getPositionBalance(address) external view returns (uint256);
    function getUserMaxWithdraw(
        uint256,
        uint256,
        address,
        uint256
    ) external view returns (uint256);
}
