// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgeReceiver {
    IChaserRegistry public registry;
    IBridgeLogic public bridgeLogic;

    mapping(address => address) public poolToCurrentPositionMarket;
    mapping(address => string) poolToCurrentMarketId;
    mapping(address => bytes32) poolToCurrentProtocolHash;
    mapping(address => uint256) positionEntranceAmount;
    mapping(bytes32 => uint256) userDepositNonce;
    mapping(bytes32 => uint256) userCumulativeDeposits;
    mapping(bytes32 => uint256) nonceToPositionValue; // key is hash of bytes of pool address and nonce
    mapping(address => address) poolToAsset;

    event AcrossMessageSent(bytes);

    event ExecutionMessage(string);

    constructor() {
        bridgeLogic = IBridgeLogic(msg.sender);
    }

    /**
     * @notice Standard Across Message reception
     * @dev This function separates messages by method and executes the different logic for each based off of the first 4 bytes of the message
     */
    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) public {
        (bytes4 method, address poolAddress, bytes memory data) = abi.decode(
            message,
            (bytes4, address, bytes)
        );

        emit ExecutionMessage("HIT");
        if (
            tokenSent != poolToAsset[poolAddress] &&
            poolToAsset[poolAddress] != address(0)
        ) {
            // IMPORTANT - HANDLE ERROR FOR WRONG ASSET BRIDGED, UNLESS METHOD IS "positionInitializer"
        }
        if (method == bytes4(keccak256(abi.encode("enterPivot")))) {
            (
                bytes32 protocolHash,
                string memory targetMarketId,
                uint256 poolNonce
            ) = abi.decode(data, (bytes32, string, uint256));

            // try
            //     ERC20(poolToAsset[poolAddress]).transfer(
            //         address(bridgeLogic),
            //         amount
            //     )
            // {
            //     emit ExecutionMessage("transfer success");
            // } catch Error(string memory reason) {
            //     emit ExecutionMessage(reason);
            // }

            try
                bridgeLogic.handleEnterPivot(
                    tokenSent,
                    amount,
                    poolAddress,
                    protocolHash,
                    targetMarketId,
                    poolNonce
                )
            {
                emit ExecutionMessage("enterPivot success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }
        if (method == bytes4(keccak256(abi.encode("userDeposit")))) {
            (bytes32 depositId, address userAddress) = abi.decode(
                data,
                (bytes32, address)
            );

            // try
            //     ERC20(poolToAsset[poolAddress]).transfer(
            //         address(bridgeLogic),
            //         amount
            //     )
            // {
            //     emit ExecutionMessage("transfer success");
            // } catch Error(string memory reason) {
            //     emit ExecutionMessage(reason);
            // }

            try
                bridgeLogic.handleUserDeposit(
                    poolAddress,
                    userAddress,
                    depositId,
                    amount
                )
            {
                emit ExecutionMessage("userDeposit success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }
        if (method == bytes4(keccak256(abi.encode("positionInitializer")))) {
            (
                bytes32 depositId,
                address userAddress,
                string memory marketId,
                bytes32 protocolHash
            ) = abi.decode(data, (bytes32, address, string, bytes32));

            // try
            //     ERC20(poolToAsset[poolAddress]).transfer(
            //         address(bridgeLogic),
            //         amount
            //     )
            // {
            //     emit ExecutionMessage("transfer success");
            // } catch Error(string memory reason) {
            //     emit ExecutionMessage(reason);
            // }

            try
                bridgeLogic.handlePositionInitializer(
                    amount,
                    poolAddress,
                    tokenSent,
                    depositId,
                    userAddress,
                    marketId,
                    protocolHash
                )
            {
                emit ExecutionMessage("positionInitializer success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }
        if (method == bytes4(keccak256(abi.encode("poolReturn")))) {
            // Receive the entire pool's funds if there are no currently viable markets or if the pool is disabled
        }
        if (method == bytes4(keccak256(abi.encode("userWithdrawOrder")))) {
            //Take amount in asset sent through bridge and totalAvailableForUser, take this proportion
            //Burn the users pool tokens based off this proportion
            //Send user their tokens
            (bytes32 withdrawId, uint256 totalAvailableForUser) = abi.decode(
                data,
                (bytes32, uint256)
            );

            // try ERC20(poolToAsset[poolAddress]).transfer(poolAddress, amount) {
            //     emit ExecutionMessage("transfer success");
            // } catch Error(string memory reason) {
            //     emit ExecutionMessage(reason);
            // }

            try
                IPoolControl(poolAddress).finalizeWithdrawOrder(
                    withdrawId,
                    amount,
                    totalAvailableForUser
                )
            {
                emit ExecutionMessage("userWithdrawOrder success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }
    }
}
