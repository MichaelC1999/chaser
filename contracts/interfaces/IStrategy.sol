pragma solidity ^0.8.19;

interface IStrategy {
    function updateStrategy(
        string calldata sourceCode,
        string calldata name
    ) external;

    function strategySourceCode() external view returns (string memory);

    function strategyName() external view returns (string memory);
}
