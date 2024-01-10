// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "hardhat/console.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {IBridgedConnector} from "./interfaces/IBridgedConnector.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract ChaserRouter is OApp {
    // contract ChaserRouter {
    // Manages LayerZero communications with other chains
    // Receives lzReceive messages from BridgedRouter, then calls the proper PoolControl functions to update state on pool

    // message structure - bytes4 method, bool isDestinationPool, address poolAddress, bytes memory data

    IChaserRegistry public registry;
    address connector;

    /**
     * @dev Constructor to initialize the omnichain contract.
     * @param _endpoint Address of the LayerZero endpoint.
     * @param _registry Address of the contract registry.
     */
    constructor(
        address _endpoint,
        address _registry
    ) OApp(_endpoint, msg.sender) {
        // constructor(address _endpoint, address _owner) {
        connector = msg.sender;
        registry = IChaserRegistry(_registry);
    }

    function send(
        uint256 _destinationChainId,
        bytes4 method,
        bool isDestinationPool,
        address poolAddress,
        bytes memory _data,
        uint256 _dstGasWei
    ) external payable {
        uint32 dstEid = registry.chainIdToEndpointId(_destinationChainId);
        bytes memory options = buildOptions(_dstGasWei);
        bytes memory message = generateSendMessage(
            method,
            isDestinationPool,
            poolAddress,
            _data
        );
        _lzSend(
            dstEid, // Destination chain's endpoint ID.
            message, // Encoded message payload being sent.
            options, // Message execution options (e.g., gas to use on destination).
            MessagingFee(msg.value, 0), // Fee struct containing native gas and ZRO token.
            payable(msg.sender) // The refund address in case the send call reverts.
        );
    }

    function methodHash(string memory method) public view returns (bytes4) {
        return bytes4(keccak256(abi.encode(method)));
    }

    function generatePayload(
        uint256 amount,
        bytes32 depositId
    ) external view returns (bytes memory) {
        return abi.encode(amount, depositId);
    }

    function generateSendMessage(
        bytes4 _method,
        bool _isDestinationPool,
        address _poolAddress,
        bytes memory _data
    ) public view returns (bytes memory payload) {
        payload = abi.encode(_method, _isDestinationPool, _poolAddress, _data);
    }

    // @dev Override receive function to enforce strict nonce enforcement.
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // IMPORTANT - NEED TO IMPLEMENT NONCED/ORDERED DELIVERY
        (
            bytes4 method,
            bool isDestinationPool,
            address poolAddress,
            bytes memory data
        ) = decodePayload(_message);

        if (isDestinationPool == true) {
            IPoolControl(poolAddress).receiveHandler(method, data);
        } else {
            IBridgedConnector(connector).receiveHandler(method, data);
        }
    }

    function decodePayload(
        bytes memory _payload
    )
        internal
        view
        returns (
            bytes4 method,
            bool isDestinationPool,
            address poolAddress,
            bytes memory data
        )
    {
        (
            bytes4 method,
            bool isDestinationPool,
            address poolAddress,
            bytes memory data
        ) = abi.decode(_payload, (bytes4, bool, address, bytes));
    }

    function buildOptions(
        uint256 _dstGasWei
    ) public view returns (bytes memory) {
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(
            OptionsBuilder.newOptions(),
            uint128(_dstGasWei),
            0
        );
        return options;
    }

    function quote(
        uint32 _dstEid, // Destination chain's endpoint ID.
        uint256 _dstGasWei,
        string memory _message // The message to send.
    ) public view returns (uint256 nativeFee) {
        bytes memory options = buildOptions(_dstGasWei);
        bytes memory _payload = abi.encode(_message);

        MessagingFee memory fee = _quote(_dstEid, _payload, options, false);
        return fee.nativeFee;
    }
}
