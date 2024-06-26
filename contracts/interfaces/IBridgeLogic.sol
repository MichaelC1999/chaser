// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgeLogic {
    function managerChainId() external view returns (uint256);
    function currentChainId() external view returns (uint256);

    function registry() external view returns (address);
    function messenger() external view returns (address);

    function bridgeReceiverAddress() external view returns (address);
    function integratorAddress() external view returns (address);

    function poolToCurrentPositionMarket(
        address
    ) external view returns (address);
    function poolToCurrentProtocolHash(address) external view returns (bytes32);
    function poolToAsset(address) external view returns (address);
    function userDepositNonce(bytes32) external view returns (uint256);
    function userCumulativeDeposits(bytes32) external view returns (uint256);
    function poolAddressToDepositNonce(address) external view returns (uint256);
    function poolAddressToWithdrawNonce(
        address
    ) external view returns (uint256);
    function poolToDepositNonceAtEntrance(
        address
    ) external view returns (uint256);
    function poolToWithdrawNonceAtEntrance(
        address
    ) external view returns (uint256);
    function poolToRescueMode(address) external view returns (bool);
    function poolToEscrowAmount(
        address,
        address
    ) external view returns (uint256);
    function poolInitialized(address) external view returns (bool);
    function poolToNonceToCumulativeDeposits(
        address,
        uint256
    ) external view returns (uint256);
    function poolToNonceToCumulativeWithdraw(
        address,
        uint256
    ) external view returns (uint256);
    function poolToPositionAtEntrance(address) external view returns (uint256);

    function initialize(uint256, uint256, address) external;

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

    function receivePivotEntranceFunds(uint256, address, address) external;

    function localPositionSetting(address) external;

    function setPivotEntranceFundsToPosition(address) external;

    function handleEnterPositionState(address, bytes memory) external;

    function handleUserDeposit(
        address,
        bytes32,
        uint256,
        uint256,
        uint256
    ) external;

    function sendPositionInitialized(address, bytes32, uint256) external;

    function sendPivotCompleted(address, uint256) external;

    function updatePositionState(address, bytes32, address) external;

    function crossChainPivot(address, uint256, address, uint256) external;

    function executeExitPivot(address, bytes memory) external;

    function protocolDeductionCalculations(
        uint256,
        uint256,
        uint256,
        address
    ) external returns (uint256);

    function protocolDeduction(uint256, uint256, address) external;

    function localPivot(address, uint256) external;

    function crossChainBridge(
        uint256,
        address,
        address,
        address,
        uint256,
        bytes memory
    ) external;

    function userWithdrawSequence(address, bytes memory) external;

    function userWithdraw(uint256, uint256, address, bytes32) external;

    function receiveDepositFromPool(uint256, address) external returns (bool);

    function handleInvalidMarketDeposit(uint256, address, address) external;

    function integratorWithdraw(address, uint256) external;

    function setNonceCumulative(address, uint256, bool) external;

    function getPositionBalance(address) external view returns (uint256);

    function getNonPendingPositionBalance(
        address,
        uint256,
        uint256
    ) external view returns (uint256);

    function assetPricePerUSDCOracle(address) external view returns (uint256);

    function getUserMaxWithdraw(
        uint256,
        uint256
    ) external view returns (uint256);

    function setEntranceState(uint256, address) external;

    function getChainlinkPrice(address) external view returns (uint256);

    function getCurrentPositionData(
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
