// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IComet} from "./interfaces/IComet.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IPoolBroker} from "./interfaces/IPoolBroker.sol";
import {DataTypes} from "./libraries/AaveDataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Integrator is Initializable {
    address public bridgeLogicAddress;
    address public registryAddress;
    uint256 chainId;

    event ExecutionMessage(string);

    function initialize(
        address _bridgeLogicAddress,
        address _registryAddress
    ) public initializer {
        bridgeLogicAddress = _bridgeLogicAddress;
        registryAddress = _registryAddress;
        IChaserRegistry(registryAddress).addIntegrator(address(this));
        chainId = IChaserRegistry(registryAddress).currentChainId();
    }

    function aaveConnection(
        bytes32 _operation,
        uint256 _amount,
        address _assetAddress,
        address _marketAddress,
        address _poolBroker
    ) internal {
        address trueAsset = _assetAddress;
        if (chainId == 11155111) {
            _assetAddress = address(0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357);
        }

        if (_operation == hasher("deposit")) {
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
    ) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
    }

    function acrossConnection(
        bytes32 _operation,
        uint256 _amount,
        address _assetAddress,
        address _marketAddress,
        address _poolBroker
    ) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
    }

    function getCurrentPosition(
        address _poolAddress,
        address _assetAddress,
        address _marketAddress,
        bytes32 _protocolHash
    ) external view returns (uint256) {
        address brokerAddress = IChaserRegistry(registryAddress)
            .poolAddressToBroker(_poolAddress);

        if (_protocolHash == hasher("aave-v3")) {
            // Default to the AAVE pool contract
            if (chainId == 11155111) {
                _assetAddress = address(
                    0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357
                );
            }

            // IN DEVELOPMENT - This contract is preloaded with aave testnet equivalent asset
            // require(IERC20(poolToAsset[_poolAddress]).balanceOf(address(this)) == _amount)

            DataTypes.ReserveData memory Reserve = IAavePool(_marketAddress)
                .getReserveData(_assetAddress);
            address aTokenAddress = Reserve.aTokenAddress;

            //-measure integrator's balance of aTokens before depo
            return IERC20(aTokenAddress).balanceOf(brokerAddress);
        }

        if (_protocolHash == hasher("compound-v3")) {
            return IComet(_marketAddress).balanceOf(brokerAddress);
        }
    }

    function hasher(string memory strToHash) public view returns (bytes32) {
        return keccak256(abi.encode(strToHash));
    }

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
