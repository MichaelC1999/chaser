pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";

interface IOptimisticOracleV3 {
    function defaultIdentifier() external view returns (bytes32);

    function getMinimumBond(address currency) external view returns (uint256);

    function settleAssertion(bytes32 assertionId) external;

    function assertTruth(
        bytes memory claim,
        address asserter,
        address callbackRecipient,
        address escalationManager,
        uint64 liveness,
        IERC20 currency,
        uint256 bond,
        bytes32 identifier,
        bytes32 domainId
    ) external returns (bytes32);
}
