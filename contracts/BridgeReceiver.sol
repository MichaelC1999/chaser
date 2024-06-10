// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserTreasury} from "./interfaces/IChaserTreasury.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BridgeReceiver is OwnableUpgradeable {
    IBridgeLogic public bridgeLogic;
    IChaserRegistry public registry;
    address spokePoolAddress;
    mapping(address => address) poolToAsset;

    function initialize(
        address _bridgeLogicAddress,
        address _spokePoolAddress,
        address _registryAddress
    ) public initializer {
        __Ownable_init();
        bridgeLogic = IBridgeLogic(_bridgeLogicAddress);
        registry = IChaserRegistry(_registryAddress);
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
        if (method == bytes4(keccak256(abi.encode("BaProtocolDeduction")))) {
            protocolDeduction(method, tokenSent, amount, poolAddress, data);
        }
    }

    function protocolDeduction(
        bytes4 _method,
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (uint256 _protocolFees, uint256 _rewardAmountInAsset) = abi.decode(
            _data,
            (uint256, uint256)
        );
        address treasuryAddress = registry.treasuryAddress();
        bool success = IERC20(_tokenSent).transfer(treasuryAddress, _amount);
        IChaserTreasury(treasuryAddress).separateProtocolFeeAndReward(
            _rewardAmountInAsset,
            _protocolFees,
            _poolAddress,
            _tokenSent
        );
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
            bytes32 protocolHash
        ) = abi.decode(_data, (bytes32, address, address, bytes32));

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
                protocolHash
            )
        {} catch Error(string memory reason) {
            bridgeLogic.returnToPool(
                _method,
                _poolAddress,
                _tokenSent,
                depositId,
                _amount
            );
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
        {} catch Error(string memory reason) {
            bridgeLogic.returnToPool(
                _method,
                _poolAddress,
                _tokenSent,
                depositId,
                _amount
            );
        }
    }

    function enterPivot(
        bytes4 _method,
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (bytes32 protocolHash, address targetMarketAddress) = abi.decode(
            _data,
            (bytes32, address)
        );

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
                targetMarketAddress
            )
        {} catch Error(string memory reason) {
            bridgeLogic.returnToPool(
                _method,
                _poolAddress,
                _tokenSent,
                bytes32(""),
                _amount
            );
        }
    }

    // This function handles the second half of failed bridging execution, returning funds to user and reseting positional state
    function poolReturn(
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes memory _data
    ) internal {
        (bytes4 originalMethod, bytes32 txId) = abi.decode(
            _data,
            (bytes4, bytes32)
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
            IPoolControl(_poolAddress).handleUndoPivot(_amount);
        }
    }
}
