// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface IChaserRouter {
    // Include public and external functions from the ChaserRouter contract

    function send(
        uint256 _destinationChainId,
        bytes4 method,
        bool isDestinationPool,
        address poolAddress,
        bytes memory _data,
        uint256 _dstGasWei
    ) external payable;

    // Any other public or external functions would be listed here

    // Note: The _lzReceive function is an internal override and is not included in the interface
}
