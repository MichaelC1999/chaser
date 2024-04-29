pragma solidity ^0.8.18;

interface IStrategy {
    function updateStrategy(
        string calldata sourceCode,
        string calldata name
    ) external;

    function strategyCode(uint256) external view returns (bytes memory);

    function strategyName(uint256) external view returns (string memory);
}
