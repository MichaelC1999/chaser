// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

interface IArbitrationContract {
    function inAssertionBlockWindow(bytes32) external view returns (bool);

    function queryMovePosition(
        address,
        bytes memory,
        bytes memory,
        string memory,
        uint256,
        uint256
    ) external returns (bytes32);

    function generateClaim(
        uint256,
        string memory,
        bytes memory,
        uint256,
        string memory,
        bytes memory
    ) external view returns (bytes memory);

    function assertionResolvedCallback(bytes32, bool) external;

    function assertionDisputedCallback(bytes32) external;

    function readAssertionRequestedPosition(
        bytes32
    ) external view returns (bytes memory, string memory, uint256, uint256);
}
