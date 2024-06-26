// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IComet} from "./interfaces/IComet.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IPoolBroker} from "./interfaces/IPoolBroker.sol";
import {DataTypes} from "./libraries/AaveDataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Integrator Contract
/// @dev Handles protocol-specific operations like deposits and withdrawals
contract Integrator is OwnableUpgradeable {
    address public bridgeLogicAddress;
    address public registryAddress;
    uint256 chainId;

    event ExecutionMessage(string);

    /// @notice Initializes the Integrator contract, replacing the constructor
    /// @param _bridgeLogicAddress Address of the BridgeLogic contract
    /// @param _registryAddress Address of the ChaserRegistry contract
    function initialize(
        address _bridgeLogicAddress,
        address _registryAddress
    ) public initializer {
        __Ownable_init();

        bridgeLogicAddress = _bridgeLogicAddress;
        registryAddress = _registryAddress;
        IChaserRegistry(registryAddress).addIntegrator(address(this));
        chainId = IChaserRegistry(registryAddress).currentChainId();
    }

    /// @notice Handles the interaction with the Aave protocol for deposit or withdrawal
    /// @dev Directly calls Aave's deposit or withdrawal functions via the Aave pool interface
    /// @dev Currently changes the asset to deposit because of testnet compatibility constraints
    /// @param _operation Type of operation to perform ('deposit' or 'withdraw')
    /// @param _amount Amount of the asset to be deposited or withdrawn
    /// @param _assetAddress Address of the asset involved in the transaction (on the local chain, not necessarily the address on the pool chain)
    /// @param _marketAddress Address of the Aave market (lending pool)
    /// @param _poolBroker Address of the PoolBroker that will hold the aTokens
    function aaveConnection(
        bytes32 _operation,
        uint256 _amount,
        address _assetAddress,
        address _marketAddress,
        address _poolBroker
    ) internal {
        address trueAsset = _assetAddress;
        // IMPORTANT - REMOVE PROTOCOL SPECIFIC TESTNET TOKEN ANALOGS
        if (chainId == 11155111) {
            _assetAddress = address(0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c);
        }
        if (chainId == 421614) {
            _assetAddress = address(0x1dF462e2712496373A347f8ad10802a5E95f053D);
        }

        if (_operation == hasher("deposit")) {
            IERC20(trueAsset).transferFrom(
                bridgeLogicAddress,
                address(this),
                _amount
            );
            IERC20(_assetAddress).approve(_marketAddress, _amount);

            IAavePool(_marketAddress).supply(
                _assetAddress,
                _amount,
                _poolBroker,
                0
            );
        }
        if (_operation == hasher("withdraw")) {
            bytes memory encodedFunction = abi.encodeWithSignature(
                "withdraw(address,uint256,address)",
                _assetAddress,
                _amount,
                _poolBroker
            );

            IPoolBroker(_poolBroker).withdrawAssets(
                _marketAddress,
                encodedFunction
            );

            bool success = IERC20(trueAsset).transfer(
                bridgeLogicAddress,
                _amount
            );
            require(success, "Token transfer failure");
        }
    }

    /// @notice Manages interactions with the Compound protocol
    /// @dev Uses the Comet contract interface to deposit to or withdraw from a Compound market
    /// @param _operation Type of operation ('deposit' or 'withdraw')
    /// @param _amount Amount of the asset to transact
    /// @param _assetAddress Address of the asset involved
    /// @param _marketAddress Address of the Compound market
    /// @param _poolBroker Address of the PoolBroker that will have access to the position
    function compoundConnection(
        bytes32 _operation,
        uint256 _amount,
        address _assetAddress,
        address _marketAddress,
        address _poolBroker
    ) internal {
        address trueAsset = _assetAddress;
        if (chainId == 11155111) {
            _assetAddress = address(0x2D5ee574e710219a521449679A4A7f2B43f046ad);
        }

        if (_operation == hasher("deposit")) {
            IERC20(trueAsset).transferFrom(
                bridgeLogicAddress,
                address(this),
                _amount
            );

            IERC20(_assetAddress).approve(_marketAddress, _amount);

            IComet(_marketAddress).supplyTo(
                _poolBroker,
                _assetAddress,
                _amount
            );
        }
        if (_operation == hasher("withdraw")) {
            bytes memory encodedFunction = abi.encodeWithSignature(
                "withdraw(address,uint256)",
                _assetAddress,
                _amount
            );

            IPoolBroker(_poolBroker).withdrawAssets(
                _marketAddress,
                encodedFunction
            );

            bool success = IERC20(trueAsset).transfer(
                bridgeLogicAddress,
                _amount
            );
            require(success, "Token transfer failure");
        }
    }

    function sparkConnection(
        bytes32 _operation,
        uint256 _amount,
        address _assetAddress,
        address _marketAddress,
        address _poolBroker
    ) internal {}

    function acrossConnection(
        bytes32 _operation,
        uint256 _amount,
        address _assetAddress,
        address _marketAddress,
        address _poolBroker
    ) internal {}

    /// @notice Retrieves the current position of a pool in a specific DeFi protocol
    /// @param _poolAddress Address of the pool querying its position
    /// @param _assetAddress Address of the asset for which the position is being queried
    /// @param _marketAddress Address of the market where the asset is deployed
    /// @param _protocolHash Hash of the protocol name
    /// @return uint256 Current balance or position amount in the protocol
    function getCurrentPosition(
        address _poolAddress,
        address _assetAddress,
        address _marketAddress,
        bytes32 _protocolHash
    ) external view returns (uint256) {
        address brokerAddress = IChaserRegistry(registryAddress)
            .poolAddressToBroker(_poolAddress);
        if (_protocolHash == bytes32("") || _marketAddress == address(0)) {
            return IERC20(_assetAddress).balanceOf(brokerAddress);
        }
        if (_protocolHash == hasher("aave-v3")) {
            // Default to the AAVE pool contract
            if (chainId == 11155111) {
                _assetAddress = address(
                    0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
                );
            }
            if (chainId == 421614) {
                _assetAddress = address(
                    0x1dF462e2712496373A347f8ad10802a5E95f053D
                );
            }

            // IN DEVELOPMENT - This contract is preloaded with aave testnet equivalent asset
            // require(IERC20(poolToAsset[_poolAddress]).balanceOf(address(this)) == _amount)

            DataTypes.ReserveData memory Reserve = IAavePool(_marketAddress)
                .getReserveData(_assetAddress);
            address aTokenAddress = Reserve.aTokenAddress;

            return IERC20(aTokenAddress).balanceOf(brokerAddress);
        }

        if (_protocolHash == hasher("compound-v3")) {
            uint256 userCollateral = IComet(_marketAddress).balanceOf(
                brokerAddress
            );
            if (userCollateral > 0) return userCollateral;

            (uint128 collateral, ) = IComet(_marketAddress).userCollateral(
                brokerAddress,
                _assetAddress
            );

            return uint256(collateral);
        }

        return 0;
    }

    /// @notice Generates a keccak256 hash of the provided string
    /// @dev Utility function to convert string to bytes32 hash, used for comparing protocol identifiers
    /// @param strToHash String to hash
    /// @return bytes32 Resulting keccak256 hash
    function hasher(string memory strToHash) public view returns (bytes32) {
        return keccak256(abi.encode(strToHash));
    }

    /// @notice Routes an external protocol interaction based on the specified operation and protocol
    /// @dev Dynamically calls the appropriate connection function based on the protocol hash
    /// @param _protocolHash Hash identifying the protocol to interact with
    /// @param _operation Operation type ('deposit', 'withdraw', etc.)
    /// @param _amount Amount of the transaction
    /// @param _poolAddress Address of the pool initiating the transaction
    /// @param _assetAddress Address of the asset involved
    /// @param _marketAddress Address of the market or protocol endpoint
    function routeExternalProtocolInteraction(
        bytes32 _protocolHash,
        bytes32 _operation,
        uint256 _amount,
        address _poolAddress,
        address _assetAddress,
        address _marketAddress
    ) external {
        require(
            msg.sender == bridgeLogicAddress,
            "Only the bridgeLogic contract may call this function"
        );
        address poolBroker = IChaserRegistry(registryAddress)
            .poolAddressToBroker(_poolAddress);
        if (poolBroker == address(0)) {
            poolBroker = IChaserRegistry(registryAddress).deployPoolBroker(
                _poolAddress,
                _assetAddress
            );
        }

        if (_protocolHash == hasher("aave-v3")) {
            aaveConnection(
                _operation,
                _amount,
                _assetAddress,
                _marketAddress,
                poolBroker
            );
        } else if (_protocolHash == hasher("compound-v3")) {
            compoundConnection(
                _operation,
                _amount,
                _assetAddress,
                _marketAddress,
                poolBroker
            );
        } else if (_protocolHash == hasher("spark")) {
            sparkConnection(
                _operation,
                _amount,
                _assetAddress,
                _marketAddress,
                poolBroker
            );
        } else if ((_protocolHash == hasher("across"))) {
            acrossConnection(
                _operation,
                _amount,
                _assetAddress,
                _marketAddress,
                poolBroker
            );
        } else {
            emit ExecutionMessage("Invalid protocol provided to integrator.");
        }
    }
}
