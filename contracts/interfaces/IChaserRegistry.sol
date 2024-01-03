// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";

interface IChaserRegistry {
    function managerChainId() external view returns (uint256);

    function currentChainId() external view returns (uint256);

    function poolEnabled(address) external returns (bool);

    function addPoolEnabled(address) external;

    function disablePool(address) external;

    function chainIdToBridgedConnector(uint256) external view returns (address);

    function chainIdToSpokePoolAddress(uint256) external view returns (address);

    function chainIdToUmaAddress(uint256) external view returns (address);

    function chainIdToEndpointId(uint256) external view returns (uint32);

    function acrossAddress() external view returns (address);

    function arbitrationContract() external view returns (address);

    function slugToChainId(string memory) external view returns (uint256);

    function slugToProtocolHash(string memory) external view returns (bytes32);

    function slugEnabled(string memory) external view returns (bool);
}
