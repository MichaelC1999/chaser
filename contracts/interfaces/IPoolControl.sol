// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPoolControl {
    function generatePayload(
        string memory name,
        uint256 amount,
        bytes32 depositId
    ) external view returns (bytes memory);

    function userWithdrawOrder() external;

    function pivotPosition() external;

    function getPositionValueWithGains() external;

    function getPositionData() external;

    function getRegistryAddress() external;

    function receiveHandler(bytes4, bytes memory) external;

    function userDepositAndSetPosition(
        uint256 amount,
        int64 relayFeePct,
        address _currentPositionAddress,
        uint256 _currentPositionChain,
        bytes32 _currentPositionProtocolHash
    ) external;

    function userDeposit(uint256 amount, int64 relayFeePct) external;

    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) external;

    function sendPositionChange(bytes32 assertionId) external;

    function queryMovePosition(
        string memory requestProtocolSlug,
        string memory requestPoolId,
        uint256 bond
    ) external;

    function readPositionBalanceResult(
        uint256 positionAmount,
        bytes32 depositId
    ) external;
}
