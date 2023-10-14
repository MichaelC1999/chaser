// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {IFunctionsConsumer} from "./interfaces/IFunctionsConsumer.sol";
import {IBridgingConduit} from "./interfaces/IBridgingConduit.sol";
import {BridgingConduit} from "./BridgingConduit.sol";

contract FunctionsConsumer is
    IFunctionsConsumer,
    FunctionsClient,
    ConfirmedOwner
{
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public donId; // DON ID for the Functions DON to which the requests are sent

    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    string public requestProtocolSlug;
    string public requestTokenAddress;

    address public bridgingConduit;

    constructor(
        address router,
        bytes32 _donId
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        donId = _donId;
        bridgingConduit = address(0x909EF9150fef193b5e00B967A3430E05903d861F);
        // This contract will be deployed by BridgingConduit for security purposes
        // Pass BridgingConduit address in constructor to call conduit functions upon request fullfillment
    }

    /**
     * @notice Set the DON ID
     * @param newDonId New DON ID
     */
    function setDonId(bytes32 newDonId) external onlyOwner {
        donId = newDonId;
    }

    /**
     * @notice Triggers an on-demand Functions request using remote encrypted secrets
     * @param source JavaScript source code
     * @param secretsLocation Location of secrets (only Location.Remote & Location.DONHosted are supported)
     * @param encryptedSecretsReference Reference pointing to encrypted secrets
     * @param args String arguments passed into the source code and accessible via the global variable `args`
     * @param bytesArgs Bytes arguments passed into the source code and accessible via the global variable `bytesArgs` as hex strings
     * @param subscriptionId Subscription ID used to pay for request (FunctionsConsumer contract address must first be added to the subscription)
     * @param callbackGasLimit Maximum amount of gas used to call the inherited `handleOracleFulfillment` method
     */
    function sendRequest(
        string calldata source,
        FunctionsRequest.Location secretsLocation,
        bytes calldata encryptedSecretsReference,
        string[] calldata args,
        bytes[] calldata bytesArgs,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) external onlyOwner {
        FunctionsRequest.Request memory req;
        req.initializeRequest(
            FunctionsRequest.Location.Inline,
            FunctionsRequest.CodeLanguage.JavaScript,
            source
        );

        string memory currentPoolId = IBridgingConduit(bridgingConduit)
            .currentDepositPoolId();
        string memory currentProtocolSlug = IBridgingConduit(bridgingConduit)
            .currentDepositProtocolSlug();
        string[] memory argsToPass = new string[](4);
        if (args.length > 0) {
            argsToPass[0] = currentPoolId;
            argsToPass[1] = currentProtocolSlug;
            argsToPass[2] = args[2];
            argsToPass[3] = args[3];

            requestProtocolSlug = args[2];
            requestTokenAddress = args[3];
            req.setArgs(argsToPass);
        }
        // if (
        //     keccak256(abi.encodePacked(requestProtocolSlug)) !=
        //     keccak256(abi.encodePacked(args[0]))
        // ) {
        //     requestProtocolSlug = args[0];
        // }
        // if (requestTokenAddress != address(bytes20(bytes(args[1])))) {
        //     requestTokenAddress = address(bytes20(bytes(args[1])));
        // }

        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            callbackGasLimit,
            donId
        );
    }

    // Write handleOracleFulfillment override function, should call functions on the conduit to execute the bridging/set position states
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal virtual override {
        s_lastResponse = response;
        s_lastError = err;

        BridgingConduit(bridgingConduit).executeMovePosition(
            string(response)
            // requestProtocolSlug,
            // requestTokenAddress
        );

        // call executeMovePosition, passing in response
    }
}
