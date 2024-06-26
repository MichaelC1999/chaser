// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";

contract PoolBroker {
    address public poolAddress;
    address public integratorAddress;
    address public bridgeLogicAddress;

    function addConfig(
        address _poolAddress,
        address _integratorAddress,
        address _bridgeLogicAddress
    ) external {
        require(
            poolAddress == address(0),
            "Can only change configs if pool or asset is invalid"
        );
        poolAddress = _poolAddress;
        integratorAddress = _integratorAddress;
        bridgeLogicAddress = _bridgeLogicAddress;
    }

    function forwardHeldFunds(uint256 _amount) external {
        require(
            msg.sender == bridgeLogicAddress,
            "Only callable by BridgeLogic"
        );
        address assetAddress = IBridgeLogic(bridgeLogicAddress).poolToAsset(
            poolAddress
        );
        IERC20(assetAddress).transfer(bridgeLogicAddress, _amount);
    }

    function withdrawAssets(
        address _marketAddress,
        bytes memory _encodedFunction
    ) external {
        require(
            msg.sender == integratorAddress,
            "Only the integrator may call this function"
        );
        // Integrator calls this function
        // Make call to external market for withdraw
        (bool success, ) = _marketAddress.call(_encodedFunction);

        require(
            success,
            "The withdraw execution was unsuccessful on the external protocol."
        );

        address assetAddress = IBridgeLogic(bridgeLogicAddress).poolToAsset(
            poolAddress
        );

        uint256 assetAmountWithdrawn = IERC20(assetAddress).balanceOf(
            address(this)
        );
        bool intSuccess = IERC20(assetAddress).transfer(
            integratorAddress,
            assetAmountWithdrawn
        );
        require(intSuccess, "Token transfer failure");
    }
}
