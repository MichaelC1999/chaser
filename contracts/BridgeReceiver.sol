// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgeReceiver {
    IBridgeLogic public bridgeLogic;
    address spokePoolAddress;

    mapping(address => address) poolToAsset;

    event AcrossMessageSent(bytes);
    event ExecutionMessage(string);

    constructor(address _bridgeLogicAddress, address _spokePoolAddress) {
        bridgeLogic = IBridgeLogic(_bridgeLogicAddress);
        spokePoolAddress = _spokePoolAddress;
    }

    function decodeMessageEvent(
        bytes memory _message
    ) external view returns (bytes4, address, bytes memory) {
        return abi.decode(_message, (bytes4, address, bytes));
    }

    /**
     * @notice Standard Across Message reception
     * @dev This function separates messages by method and executes the different logic for each based off of the first 4 bytes of the message
     */
    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address relayer,
        bytes memory message
    ) external {
        //IMPORTANT - A USER COULD BRIDGE WITH CUSTOM MANIPULATIVE MESSAGE FROM OWN CONTRACT. THE USER STILL HAS TO SEND amount IN ASSET, BUT THIS COULD EXPLOIT SOMETHING
        require(
            msg.sender == spokePoolAddress,
            "Only the Across V3 Spokepool can handle these messages"
        );
        (bytes4 method, address poolAddress, bytes memory data) = abi.decode(
            message,
            (bytes4, address, bytes)
        );

        if (
            tokenSent != poolToAsset[poolAddress] &&
            poolToAsset[poolAddress] != address(0)
        ) {
            // IMPORTANT - HANDLE ERROR FOR WRONG ASSET BRIDGED, UNLESS METHOD IS "positionInitializer"
        }
        if (
            method == bytes4(keccak256(abi.encode("BbPivotBridgeMovePosition")))
        ) {
            enterPivot(method, tokenSent, amount, poolAddress, data);
        }
        if (method == bytes4(keccak256(abi.encode("AbBridgeDepositUser")))) {
            userDeposit(method, tokenSent, amount, poolAddress, data);
        }
        if (
            method ==
            bytes4(keccak256(abi.encode("AbBridgePositionInitializer")))
        ) {
            positionInitializer(method, tokenSent, amount, poolAddress, data);
        }
        if (method == bytes4(keccak256(abi.encode("BaReturnToPool")))) {
            poolReturn(method, tokenSent, amount, poolAddress, data);
        }
        if (
            method == bytes4(keccak256(abi.encode("BaBridgeWithdrawOrderUser")))
        ) {
            (
                bytes32 withdrawId,
                uint256 totalAvailableForUser,
                uint256 positionValue,
                uint256 inputAmount
            ) = abi.decode(data, (bytes32, uint256, uint256, uint256));

            ERC20(tokenSent).transfer(poolAddress, amount);

            try
                IPoolControl(poolAddress).finalizeWithdrawOrder(
                    withdrawId,
                    amount,
                    totalAvailableForUser,
                    positionValue,
                    inputAmount
                )
            {
                emit ExecutionMessage("BaBridgeWithdrawOrderUser success");
            } catch Error(string memory reason) {
                // IMPORTANT - RESCUE WITHDRAW CALLBACK LOGIC
                emit ExecutionMessage(reason);
            }
        }
    }

    function positionInitializer(
        bytes4 _method,
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (
            bytes32 depositId,
            address userAddress,
            address marketAddress,
            string memory marketId,
            bytes32 protocolHash
        ) = abi.decode(_data, (bytes32, address, address, string, bytes32));

        ERC20(_tokenSent).transfer(address(bridgeLogic), _amount);

        try
            bridgeLogic.handlePositionInitializer(
                _amount,
                _poolAddress,
                _tokenSent,
                depositId,
                userAddress,
                marketAddress,
                marketId,
                protocolHash
            )
        {
            emit ExecutionMessage("AbBridgePositionInitializer success");
        } catch Error(string memory reason) {
            bridgeLogic.returnToPool(_method, _poolAddress, depositId, _amount);
            emit ExecutionMessage(reason);
        }
    }

    function userDeposit(
        bytes4 _method,
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (bytes32 depositId, address userAddress) = abi.decode(
            _data,
            (bytes32, address)
        );

        ERC20(_tokenSent).transfer(address(bridgeLogic), _amount);

        try
            bridgeLogic.handleUserDeposit(
                _poolAddress,
                userAddress,
                depositId,
                _amount
            )
        {
            emit ExecutionMessage("AbBridgeDepositUser success");
        } catch Error(string memory reason) {
            bridgeLogic.returnToPool(_method, _poolAddress, depositId, _amount);
            emit ExecutionMessage(reason);
        }
    }

    function enterPivot(
        bytes4 _method,
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (
            bytes32 protocolHash,
            address targetMarketAddress,
            string memory targetMarketId,
            uint256 poolNonce
        ) = abi.decode(_data, (bytes32, address, string, uint256));

        ERC20(_tokenSent).transfer(address(bridgeLogic), _amount);

        try
            bridgeLogic.handleEnterPivot(
                _tokenSent,
                _amount,
                _poolAddress,
                protocolHash,
                targetMarketAddress,
                targetMarketId,
                poolNonce
            )
        {
            emit ExecutionMessage("BbPivotBridgeMovePosition success");
        } catch Error(string memory reason) {
            bridgeLogic.returnToPool(
                _method,
                _poolAddress,
                bytes32(""),
                _amount
            );
            emit ExecutionMessage(reason);
        }
    }

    // This function handles the second half of failed bridging execution, returning funds to user and reseting positional state
    function poolReturn(
        bytes4 _method,
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        //IMPORTANT - HERE NEED TO SEPARATE LOGIC FOR FAILED/REFUNDED BRIDGING ACTIONS (depoSet,depo,pivot)
        //IMPORTANT - MUST CALL FUNCTIONS ON *POOL*, THIS FUNCTION IS ONLY POSSIBLE ON POOL CHAIN
        (bytes4 originalMethod, bytes32 depositId, uint256 amount) = abi.decode(
            _data,
            (bytes4, bytes32, uint256)
        );

        if (
            originalMethod ==
            bytes4(keccak256(abi.encode("AbBridgePositionInitializer")))
        ) {
            // userHasPendingDeposit[msg.sender] = false;
            // targetPositionMarketId = "";
            // targetPositionChain = 0;
            // targetPositionProtocolHash = bytes32("");
            // poolNonce = 0;
            // pivotPending = false;
            // address originalSender = poolCalc.depositIdToDepositor(depositId);
            // // undo poolCalc.createDepositOrder
            // depositIdToDepositor[depositId] = address(0);
            // depositIdToDepositAmount[depositId] = 0;
            // //Return funds
            // ERC20(_tokenSent).transfer(originalSender, _amount);
        }

        if (
            originalMethod ==
            bytes4(keccak256(abi.encode("AbBridgeDepositUser")))
        ) {
            // address originalSender = poolCalc.depositIdToDepositor(depositId);
            // // undo poolCalc.createDepositOrder
            // depositIdToDepositor[depositId] = address(0);
            // depositIdToDepositAmount[depositId] = 0;
            // //Return funds
            // ERC20(_tokenSent).transfer(originalSender, _amount);
        }

        if (
            originalMethod ==
            bytes4(keccak256(abi.encode("BbPivotBridgeMovePosition")))
        ) {
            //IMPORTANT - MAYBE NEED NONCE FROM EXITPIVOT? TO MATCH POOL NONCE
            // lastPositionAddress = currentPositionAddress;
            // lastPositionChain = currentPositionChain;
            // lastPositionProtocolHash = currentPositionProtocolHash;
            // currentPositionAddress = _poolAddress;
            // currentPositionMarketId = "";
            // currentPositionChain = localChainId;
            // currentPositionProtocolHash = keccak256(abi.encode(""));
            // currentRecordPositionValue = _amount;
            // currentPositionValueTimestamp = block.timestamp;
            // targetPositionMarketId = "";
            // targetPositionChain = 0;
            // targetPositionProtocolHash = bytes32("");
            // poolNonce = nonce;
            // pivotPending = false;
            // //reset position state
            // //transfer funds to pool
            // ERC20(_tokenSent).transfer(_poolAddress, _amount);
        }
    }
}
