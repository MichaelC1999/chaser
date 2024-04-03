// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPoolBroker {
    function addConfig(address, address, address) external;

    function withdrawAssets(address, bytes memory) external;
}
