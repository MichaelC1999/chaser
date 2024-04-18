// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

interface IArbitrationContract {
    function getData(bytes32) external view returns (bool, bytes memory);

    function queryMovePosition(
        address,
        uint256,
        string memory,
        string memory,
        uint256,
        string memory,
        string memory,
        uint256,
        uint256
    ) external;

    function assertDataFor(
        bytes memory,
        address,
        uint256
    ) external returns (bytes32);

    function assertionResolvedCallback(bytes32, bool) external;

    function assertionDisputedCallback(bytes32) external;
}
