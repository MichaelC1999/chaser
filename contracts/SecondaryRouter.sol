// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SecondaryRouter {
    address public currentPoolAddress;

    constructor() {}

    function moveToCurrentPosition() external {
        // This function is indifferent to whether or not there are already deposits in current porition
        // Push funds sitting in address(this) to currentPoolAddress, calling the appropriate protocol functions to deposit()
        // Presumed that this is called after bridging funds to this contract
        // In cases funds are bridged to this subconduit with a specified position to deposit funds, it is assumed that the currentPoolAddress etc state have been updated, therefore this function will push to the "new" pool
    }

    function withdrawPosition() external {
        // Withdraw funds from current position to this subconduit
        // Instantiate the currentPoolAddress with the ExternalFunctionConstructor Interface
        // Call the ExternalFunctionConstructor withdraw method
    }

    function returnToConduit() external {
        // Withdraw funds from current position to this subconduit (if current position has funds)
        // Within same tx, unbridge funds sitting in subconduit back to conduit
    }

    function setCurrentPosition() external {
        // Set the state for current protocol/pool address target
    }

    function bridgeToNewChain() external {
        // Withdraw funds from current position
        // Bridge funds to conduit on other chain (the conduit sets the state on other chain, no need here. just send money)
    }

    function ccipReceive() external {
        // Receive the CCIP message from conduit and route it conditionally to the appropriate function call
        //*********
        // ReceiveWithdrawPosition
        // SetCurrentPosition
        // ReceiveReturnToConduit
        // BridgeToNewChain
    }

    function updateLedger() external {
        // Implementation
    }
}
