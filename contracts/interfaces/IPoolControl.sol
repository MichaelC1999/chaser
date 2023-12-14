pragma solidity ^0.8.9;

interface IPoolControl {
    function assetAddress() external returns (address);

    function updateAsset(address) external;

    function pivotPoolPosition(bytes32) external;
}
