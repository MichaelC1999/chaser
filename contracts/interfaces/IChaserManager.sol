pragma solidity ^0.8.9;

interface IChaserManager {
    function createNewPool(
        address,
        uint256,
        string memory,
        uint256,
        uint256,
        uint256
    ) external;
}
