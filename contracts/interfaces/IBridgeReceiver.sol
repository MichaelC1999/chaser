// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgeReceiver {
    function handleV3AcrossMessage(
        address,
        uint256,
        address,
        bytes memory
    ) external;
}
