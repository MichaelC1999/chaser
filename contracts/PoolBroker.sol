// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PoolBroker {
    address public poolAddress;
    address public assetAddress;
    address public integratorAddress;

    function addConfig(
        address _poolAddress,
        address _assetAddress,
        address _integratorAddress
    ) external {
        require(
            _poolAddress == address(0) ||
                assetAddress == address(0) ||
                integratorAddress == address(0),
            "Can only change configs if pool or asset is invalid"
        );
        poolAddress = _poolAddress;
        assetAddress = _assetAddress;
        integratorAddress = _integratorAddress;
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
        (bool success, bytes memory returnData) = _marketAddress.call(
            _encodedFunction
        );

        require(
            success,
            "The withdraw execution was unsuccessful on the external protocol."
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
