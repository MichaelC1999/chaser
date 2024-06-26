// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPoolControl {
    function deployingUser() external view returns (address);
    function localChain() external view returns (uint256);
    function poolToken() external view returns (address);
    function poolName() external view returns (string memory);
    function strategyIndex() external view returns (uint256);
    function openAssertion() external view returns (bytes32);
    function currentPositionChain() external view returns (uint256);
    function proposalRewardUSDC() external view returns (uint256);
    function assertionSender() external view returns (address);
    function localBridgeReceiver() external view returns (address);
    function pivotExitsFromPrevTarget() external view returns (bool);
    function localBridgeLogic() external view returns (address);
    function manager() external view returns (address);
    function registry() external view returns (address);
    function poolCalculations() external view returns (address);
    function arbitrationContract() external view returns (address);
    function asset() external view returns (address);

    function initialize(
        address,
        address,
        uint256,
        string memory,
        uint256,
        uint256,
        address,
        address,
        address
    ) external;

    function userDepositAndSetPosition(
        uint256,
        uint256,
        string memory,
        bytes memory,
        uint256
    ) external;

    function userDeposit(uint256, uint256) external;

    function userWithdrawOrder(uint256) external;

    function queryMovePosition(
        string memory,
        bytes memory,
        uint256,
        bool
    ) external;

    function sendPositionChange(bytes memory, string memory, uint256) external;

    function receivePositionInitialized(bytes memory) external;

    function pivotCompleted(address, uint256) external;

    function setWithdrawReceived(bytes32, uint256) external;

    function receivePositionBalanceWithdraw(bytes memory) external;

    function enterFundsCrossChain(
        uint256,
        address,
        uint256,
        bytes memory
    ) external;

    function crossChainBridge(
        address,
        address,
        address,
        uint256,
        uint256,
        uint256,
        bytes memory
    ) external;

    function receivePositionBalanceDeposit(bytes memory) external;

    function positionLocationForQuery(
        bool
    ) external returns (string memory, bytes memory, uint256);

    function mintUserPoolTokens(bytes32) external;

    function spokePoolPreparation(address, uint256) external;

    function _pivotCompleted(address, uint256) external;
}
