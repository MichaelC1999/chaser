// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgedConnector {
    // Include public and external functions from BridgedConnector contract

    function chaserRouter() external view returns (address);

    function receiveHandler(bytes4 method, bytes memory data) external;

    function sendPositionBalance(bytes32 depositId) external;

    function sendPositionData() external;

    function sendRegistryAddress() external;

    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) external;

    function extractMessageMethod(
        bytes memory message
    ) external view returns (bytes4 method, bytes memory data);

    function extractMessageComponents(
        bytes memory message
    ) external view returns (bytes4 method);
}
