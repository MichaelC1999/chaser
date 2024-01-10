// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPoolControl {
    // Public state variables as view functions
    function localChain() external view returns (uint256);

    function poolId() external view returns (bytes32);

    function deployingUser() external view returns (address);

    function poolNonce() external view returns (uint256);

    function poolName() external view returns (string memory);

    function strategySource() external view returns (string memory);

    function router() external view returns (address);

    function localBridgedConnector() external view returns (address);

    function manager() external view returns (address);

    function registry() external view returns (address);

    function poolToken() external view returns (address);

    function asset() external view returns (address);

    function targetPositionMarketId() external view returns (string memory);

    function targetPositionChain() external view returns (uint256);

    function targetPositionProtocolHash() external view returns (bytes32);

    function currentPositionAddress() external view returns (address);

    function currentPositionMarketId() external view returns (string memory);

    function currentPositionChain() external view returns (uint256);

    function currentPositionProtocolHash() external view returns (bytes32);

    function currentRecordPositionValue() external view returns (uint256);

    function lastPositionAddress() external view returns (address);

    function lastPositionChain() external view returns (uint256);

    function lastPositionProtocolHash() external view returns (bytes32);

    function currentPositionAssertion() external view returns (bytes32);

    function pivotPending() external view returns (bool);

    // External/Public functions
    function initializeContractConnections(address) external;

    function receiveHandler(bytes4, bytes memory) external;

    function handleAcrossMessage(
        address,
        uint256,
        bool,
        address,
        bytes memory
    ) external;

    function userWithdrawOrder(uint256) external payable;

    function pivotPosition() external payable;

    function readPositionBalance() external payable;

    function getPositionData() external payable;

    function getRegistryAddress() external payable;

    function userDepositAndSetPosition(
        uint256,
        int64,
        string memory,
        uint256,
        string memory
    ) external;

    function userDeposit(uint256, int64) external;

    function sendPositionChange(bytes32) external payable;

    function queryMovePosition(string memory, string memory, uint256) external;

    function pivotCompleted(address, uint256) external;

    function generateAcrossMessage(
        string memory,
        bytes32,
        uint256
    ) external view returns (bytes memory);
}
