// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "./interfaces/IERC20.sol";
import {SpokePoolInterface} from "./interfaces/ISpokePoolInterface.sol";

contract SubConduit {
    address public currentPoolAddress;

    address public spokePoolAddress;

    address public depositTokenAddress;

    bytes public currentDepositWithdrawBytes;

    // The token that denominates deposit + profit on the target protocol
    address currentPositionTokenAddress;

    address currentSpenderAddress;

    constructor() {}

    // How does the conduit interact with this contract when a new position is identified?
    // If funds on this chain deposited into position, cross chain call to withdraw this position
    // If new position is on other chain, cross chain call to bridge all funds in this subconduit
    // If new position is on this chain, cross chain call to set deposit target state in this contract
    // Function to call cross chain to move funds sitting in subconduit to deposit target via ExternalIntegrationFunctions contract function signature
    // WithdrawToSpark function that bridges funds back to mainnet and sends to the appropriate spark address, sends cross chain call to conduit for adjusting appropriate state

    function moveToCurrentPosition(
        bytes calldata depositDataSig,
        bytes calldata withdrawDataSig,
        address spenderAddress,
        address newPositionTokenAddress
    ) external returns (bytes memory) {
        uint subConduitBalance = IERC20(depositTokenAddress).balanceOf(
            address(this)
        );
        currentDepositWithdrawBytes = withdrawDataSig;
        currentPositionTokenAddress = newPositionTokenAddress;
        currentSpenderAddress = spenderAddress;
        IERC20(depositTokenAddress).approve(spenderAddress, subConduitBalance);
        (bool success, bytes memory returnData) = currentPoolAddress.call(
            depositDataSig
        );

        return returnData;
        // dataSig is the constructor function signature + data bytes to execute call() to make deposit to currentPoolAddress
        // This function is indifferent to whether or not there are already deposits in current porition
        // Push funds sitting in address(this) to currentPoolAddress, calling the appropriate protocol functions to deposit()
        // Presumed that this is called after bridging funds to this contract
        // In cases funds are bridged to this subconduit with a specified position to deposit funds, it is assumed that the currentPoolAddress etc state have been updated, therefore this function will push to the "new" pool
    }

    function withdrawPosition(bytes memory dataSig) public {
        uint positionTokenBalance = IERC20(currentPositionTokenAddress)
            .balanceOf(address(this));
        IERC20(currentPositionTokenAddress).approve(
            currentSpenderAddress,
            positionTokenBalance
        );
        currentPoolAddress.call(dataSig);
        // dataSig is the constructor function signature + data bytes to execute call() to make withdraw from currentPoolAddress
        // Withdraw funds from current position to this subconduit
        // Instantiate the currentPoolAddress with the ExternalIntegrationFunctions Interface
        // Call the ExternalIntegrationFunctions withdraw method
        // should be called before updating current position in case of moving to new position
    }

    function returnToSpark() public {
        // Withdraw funds from current position to this subconduit (if current position has funds)
        // Within same tx, unbridge funds sitting in subconduit back to conduit
        bytes memory datasig = currentDepositWithdrawBytes;
        withdrawPosition(datasig);
        address sparkMainnetAddress = address(0);
        bridgeToNewChain(sparkMainnetAddress, 1);
    }

    function setCurrentPosition(
        address newPoolAddress,
        address newDepositToken
    ) public {
        // Set the state for current protocol/pool address target
        currentPoolAddress = newPoolAddress;
        depositTokenAddress = newDepositToken;
    }

    function bridgeToNewChain(
        address destinationAddress,
        uint256 destinationChainId
    ) public {
        // Withdraw funds from current position
        // Bridge funds to conduit on other chain (the conduit sets the state on other chain, no need here. just send money)

        uint depositTokenBalance = IERC20(depositTokenAddress).balanceOf(
            address(this)
        );

        // UPDATE LEDGERS AND BALANCES
        uint256 maxuint = 2 ** 256 - 1;
        // Define the spokepool in constructor of subconduit
        SpokePoolInterface spokePool = SpokePoolInterface(spokePoolAddress);
        // ERC20 APPROVE
        IERC20(depositTokenAddress).approve(
            spokePoolAddress,
            depositTokenBalance
        );
        spokePool.deposit(
            destinationAddress,
            depositTokenAddress,
            depositTokenBalance,
            destinationChainId,
            49114542100000000,
            uint32(block.timestamp),
            "",
            maxuint
        );
    }

    function ccipReceive(uint action) external {
        // Receive the CCIP message from conduit and route it conditionally to the appropriate function call
        //*********
        // ReceiveWithdrawPosition
        // SetCurrentPosition
        // ReceiveReturnToConduit
        // BridgeToNewChain
        // **** NICE TO HAVE CCIP INTEGRATION
        // if (action == 1) {
        //     moveToCurrentPosition();
        // }
        // if (action == 2) {
        //     withdrawPosition();
        // }
        // if (action == 3) {
        //     returnToSpark();
        // }
        // if (action == 4) {
        //     setCurrentPosition();
        // }
        // if (action == 5) {
        //     bridgeToNewChain(destinationAddress, destinationChainId);
        // }
    }

    function developmentWithdraw() external {
        // function to withdraw bridged funds
        // ONLY FOR DEVELOPMENT, REMOVE IN PRODUCTION
        uint depositTokenBalance = IERC20(depositTokenAddress).balanceOf(
            address(this)
        );

        IERC20(depositTokenAddress).transfer(msg.sender, depositTokenBalance);
    }
}
