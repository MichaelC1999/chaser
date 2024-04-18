// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InvestmentStrategy {
    uint256 strategyCount = 0;

    mapping(uint256 => bytes) public strategyCode;
    mapping(uint256 => string) public strategyName;

    constructor() {}

    function addStrategy(bytes memory sourceCode, string memory name) public {
        strategyCode[strategyCount] = sourceCode;
        strategyName[strategyCount] = name;
        strategyCount += 1;
    }
}
