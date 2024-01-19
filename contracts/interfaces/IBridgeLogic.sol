// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgeLogic {
    // Public state variables as view functions
    function managerChainId() external view returns (uint256);

    function deployConnections(address) external returns (address, address);

    function registry() external view returns (address);

    function router() external view returns (address);

    function poolToCurrentPositionMarket(
        address
    ) external view returns (address);

    function poolToCurrentMarketId(
        address
    ) external view returns (string memory);

    function poolToCurrentProtocolHash(address) external view returns (bytes32);

    function positionEntranceAmount(address) external view returns (uint256);

    function poolToAsset(address) external view returns (address);

    function userDepositNonce(bytes32) external view returns (uint256);

    function userCumulativeDeposits(bytes32) external view returns (uint256);

    function nonceToPositionValue(bytes32) external view returns (uint256);

    function bridgeNonce(address) external view returns (uint256);

    function testFlag() external view returns (bool);

    function setPeer(uint256, address) external;

    function receiveHandler(bytes4, bytes memory) external;

    function handleAcrossMessage(
        address,
        uint256,
        bool,
        address,
        bytes memory
    ) external;

    function handleUserDeposit(address, address, bytes32, uint256) external;

    function handlePositionInitializer(
        uint256,
        address,
        address,
        bytes32,
        address,
        string memory,
        bytes32
    ) external;

    function handleEnterPivot(
        address,
        uint256,
        address,
        bytes32,
        string memory,
        uint256
    ) external;

    function readBalanceAtNonce(
        address,
        uint256
    ) external view returns (uint256);

    function getPositionBalance(address) external view returns (uint256);

    function getUserMaxWithdraw(
        uint256,
        uint256,
        address,
        uint256
    ) external view returns (uint256);

    function initializePoolPosition(
        address,
        address,
        bytes32,
        string memory,
        uint256,
        uint256
    ) external;

    function executeExitPivot(
        address,
        uint256,
        bytes32,
        string memory,
        uint256,
        address
    ) external;

    function receiveDepositFromPool(
        uint256,
        bytes32,
        address,
        address
    ) external;

    function getMarketAddressFromId(
        string memory,
        bytes32
    ) external view returns (address);
}
