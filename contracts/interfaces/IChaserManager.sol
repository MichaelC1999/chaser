pragma solidity ^0.8.9;

interface IChaserManager {
    function createNewPool(address, uint, uint256, string memory) external;
}
