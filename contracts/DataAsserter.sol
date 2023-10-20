// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./ClaimData.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import {BridgingConduit} from "./BridgingConduit.sol";

// This contract allows assertions on any form of data to be made using the UMA Optimistic Oracle V3 and stores the
// proposed value so that it may be retrieved on chain. The dataId is intended to be an arbitrary value that uniquely
// identifies a specific piece of information in the consuming contract and is replaceable. Similarly, any data
// structure can be used to replace the asserted data.
interface OptimisticOracleV3Interface {
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

contract DataAsserter {
    IERC20 public immutable defaultCurrency;
    OptimisticOracleV3Interface public immutable oo;
    // 3 minute liveness
    uint64 public constant assertionLiveness = 30;
    bytes32 public immutable defaultIdentifier;
    address public bridgingConduit;

    struct DataAssertion {
        bytes32 dataId; // The dataId that was asserted.
        bytes data; // This could be an arbitrary data type.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    mapping(bytes32 => DataAssertion) public assertionsData;

    event DataAsserted(
        bytes32 indexed dataId,
        bytes data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    event DataAssertionResolved(
        bytes32 indexed dataId,
        bytes data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    constructor(address _defaultCurrency, address _optimisticOracleV3) {
        defaultCurrency = IERC20(_defaultCurrency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
        bridgingConduit = msg.sender;
    }

    // For a given assertionId, returns a boolean indicating whether the data is accessible and the data itself.
    function getData(
        bytes32 assertionId
    ) public view returns (bool, bytes memory) {
        if (!assertionsData[assertionId].resolved)
            return (false, abi.encode(0));
        return (true, assertionsData[assertionId].data);
    }

    ///  @dev assertDataFor Opens the UMA assertion that must be verified using the strategy script provided
    function assertDataFor(
        bytes32 dataId,
        bytes memory data,
        address asserter
    ) public returns (bytes32 assertionId) {
        asserter = asserter == address(0) ? msg.sender : asserter;
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.transferFrom(msg.sender, address(this), bond);
        defaultCurrency.approve(address(oo), bond);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Data asserted: ", // in the example data is type bytes32 so we add the hex prefix 0x.
                data,
                " for using the startegy logic located at: ",
                ClaimData.toUtf8Bytes(dataId),
                " and asserter: 0x",
                ClaimData.toUtf8BytesAddress(asserter),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            asserter,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            defaultCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );
        assertionsData[assertionId] = DataAssertion(
            dataId,
            data,
            asserter,
            false
        );
        emit DataAsserted(dataId, data, asserter, assertionId);
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public {
        require(msg.sender == address(oo));
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            assertionsData[assertionId].resolved = true;
            DataAssertion memory dataAssertion = assertionsData[assertionId];
            emit DataAssertionResolved(
                dataAssertion.dataId,
                dataAssertion.data,
                dataAssertion.asserter,
                assertionId
            );
            ///  @dev Execute logic on BridgingConduit to move funds and update states
            BridgingConduit(bridgingConduit).executeMovePosition(assertionId);
        } else delete assertionsData[assertionId];
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public {}
}
