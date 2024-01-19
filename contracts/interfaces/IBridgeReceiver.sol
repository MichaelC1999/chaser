// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgeReceiver {
    function handleAcrossMessage(
        address,
        uint256,
        bool,
        address,
        bytes memory
    ) external;
}
