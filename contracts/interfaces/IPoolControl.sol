// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPoolControl {
    function receivePositionInitialized(bytes memory) external;
    function receivePositionBalance(bytes memory) external;
    function userWithdrawOrder(uint256) external;
    function readPositionBalance() external;
    function userDepositAndSetPosition(
        uint256,
        uint256,
        string memory,
        bytes memory,
        uint256
    ) external;
    function userDeposit(uint256, uint256) external;
    function handleUndoPositionInitializer(bytes32, uint256) external;
    function handleUndoDeposit(bytes32, uint256) external;
    function handleUndoPivot(uint256) external;
    function queryMovePosition(string memory, bytes memory, uint256) external;
    function sendPositionChange(bytes memory, string memory, uint256) external;
    function pivotCompleted(address, uint256) external;
    function finalizeWithdrawOrder(
        bytes32,
        uint256,
        uint256,
        uint256,
        uint256
    ) external;
    function readPoolCurrentPositionData()
        external
        view
        returns (
            address,
            bytes32,
            uint256,
            uint256,
            uint256,
            string memory,
            bytes memory
        );

    function readAssertionRequestedPosition()
        external
        view
        returns (bytes memory, string memory, uint256, uint256);

    function readStrategyCode() external view returns (string memory);

    // External/Public State Variable Accessors
    function localChain() external view returns (uint256);
    function poolToken() external view returns (address);
    function poolName() external view returns (string memory);
    function strategyIndex() external view returns (uint256);
    function pivotPending() external view returns (bool);
    function localBridgeLogic() external view returns (address);
    function manager() external view returns (address);
    function registry() external view returns (address);
    function poolCalculations() external view returns (address);
    function arbitrationContract() external view returns (address);
    function asset() external view returns (address);
    function currentPositionChain() external view returns (uint256);
}
