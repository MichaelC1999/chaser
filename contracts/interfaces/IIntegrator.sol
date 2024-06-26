// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IIntegrator {
    function routeExternalProtocolInteraction(
        bytes32,
        bytes32,
        uint256,
        address,
        address,
        address
    ) external;

    function getCurrentPosition(
        address,
        address,
        address,
        bytes32
    ) external view returns (uint256);

    function marketIdAddressToTrueAddress(
        bytes32,
        address
    ) external view returns (address);
}
