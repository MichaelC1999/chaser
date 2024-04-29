// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        // IMPORTANT - !!! A USER COULD BRIDGE WITH CUSTOM MANIPULATIVE MESSAGE FROM OWN CONTRACT. THE USER STILL HAS TO SEND amount IN ASSET, BUT THIS COULD EXPLOIT SOMETHING
        // require(
        //     msg.sender == spokePoolAddress,
        //     "Only the Across V3 Spokepool can handle these messages"
        // ); // IMPORTANT - UNCOMMENT IN PRODUCTION
        (bytes4 method, address poolAddress, bytes memory data) = abi.decode(
            message,
            (bytes4, address, bytes)
        );

        if (poolToAsset[poolAddress] == address(0)) {
            poolToAsset[poolAddress] = tokenSent;
        }

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
            poolReturn(tokenSent, amount, poolAddress, data);
        }
        if (
            method == bytes4(keccak256(abi.encode("BaBridgeWithdrawOrderUser")))
        ) {
            finalizeWithdraw(method, tokenSent, amount, poolAddress, data);
        }
    }

    function finalizeWithdraw(
        bytes4 _method,
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (
            bytes32 withdrawId,
            uint256 totalAvailableForUser,
            uint256 positionValue,
            uint256 inputAmount
        ) = abi.decode(_data, (bytes32, uint256, uint256, uint256));

        bool success = IERC20(_tokenSent).transfer(_poolAddress, _amount);
        require(success, "Token transfer failure");

        IPoolControl(_poolAddress).finalizeWithdrawOrder(
            withdrawId,
            _amount,
            totalAvailableForUser,
            positionValue,
            inputAmount
        );
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

        bool success = IERC20(_tokenSent).transfer(
            address(bridgeLogic),
            _amount
        );
        require(success, "Token transfer failure");

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
            bridgeLogic.returnToPool(
                _method,
                _poolAddress,
                depositId,
                _amount,
                0
            );
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
        (bytes32 depositId, uint256 withdrawNonce) = abi.decode(
            _data,
            (bytes32, uint256)
        );

        bool success = IERC20(_tokenSent).transfer(
            address(bridgeLogic),
            _amount
        );
        require(success, "Token transfer failure");

        try
            bridgeLogic.handleUserDeposit(
                _poolAddress,
                depositId,
                withdrawNonce,
                _amount
            )
        {
            emit ExecutionMessage("AbBridgeDepositUser success");
        } catch Error(string memory reason) {
            bridgeLogic.returnToPool(
                _method,
                _poolAddress,
                depositId,
                _amount,
                0
            );
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

        bool success = IERC20(_tokenSent).transfer(
            address(bridgeLogic),
            _amount
        );
        require(success, "Token transfer failure");

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
                _amount,
                poolNonce
            );
            emit ExecutionMessage(reason);
        }
    }

    // This function handles the second half of failed bridging execution, returning funds to user and reseting positional state
    function poolReturn(
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (bytes4 originalMethod, bytes32 txId, uint256 poolNonce) = abi.decode(
            _data,
            (bytes4, bytes32, uint256)
        );

        if (
            originalMethod ==
            bytes4(keccak256(abi.encode("AbBridgePositionInitializer")))
        ) {
            IERC20(_tokenSent).approve(_poolAddress, _amount);
            IPoolControl(_poolAddress).handleUndoPositionInitializer(
                txId,
                _amount
            );
        }

        if (
            originalMethod ==
            bytes4(keccak256(abi.encode("AbBridgeDepositUser")))
        ) {
            IERC20(_tokenSent).approve(_poolAddress, _amount);
            IPoolControl(_poolAddress).handleUndoDeposit(txId, _amount);
        }

        if (
            originalMethod ==
            bytes4(keccak256(abi.encode("BbPivotBridgeMovePosition")))
        ) {
            bool success = IERC20(_tokenSent).transfer(
                address(bridgeLogic),
                _amount
            );
            require(success, "Token transfer failure");
            IPoolControl(_poolAddress).handleUndoPivot(poolNonce, _amount);
        }
    }
}
