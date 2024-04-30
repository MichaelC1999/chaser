// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

interface IArbitrationContract {
    function inAssertionBlockWindow(bytes32) external view returns (bool);

    function queryMovePosition(
        address,
        uint256,
        string memory,
        bytes memory,
        uint256,
        string memory,
        bytes memory,
        uint256,
        uint256
    ) external returns (bytes32);

    function assertDataFor(
        bytes memory,
        address,
        uint256
    ) external returns (bytes32);

    function assertionResolvedCallback(bytes32, bool) external;

    function assertionDisputedCallback(bytes32) external;
}
