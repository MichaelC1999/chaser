// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IComet} from "./interfaces/IComet.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IPoolBroker} from "./interfaces/IPoolBroker.sol";
import {DataTypes} from "./libraries/AaveDataTypes.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Integrator {
    // THIS CONTRACT HOLDS THE LP TOKENS, ROUTES THE DEPOSITS, FULFILLS WITHDRAWS FROM THESE EXTERNAL PROTOCOLS
    //THE CONNECTION FUNCTIONS ARE ONLY CALLED FROM BridgeLogic
    // DEPOSIT REQUESTS ALWAYS TRANSFER THE ERC20 TOKENS TO THIS CONTRACT, WHICH THEN APPROVES THE EXTERNAL PROTOCOL FOR TRANSFERING
    //ON USER DEPOSITS, RETURN THE NUMBER OF ATOKENS MINTED FOR THIS NEW DEPOSIT. OR SHOULD IT JUST RETURN TOTAL NUMBER OF ATOKENS FOR USER?
    // WITHDRAW REQUESTS CLEARS STATE AND TRANSFERS ASSET TO THE BridgeLogic

    address public bridgeLogicAddress;
    address public registryAddress;
    uint256 chainId;
    event ExecutionMessage(string);

    constructor(address _bridgeLogicAddress, address _registryAddress) {
        bridgeLogicAddress = _bridgeLogicAddress;
        registryAddress = _registryAddress;
        IChaserRegistry(registryAddress).addIntegrator(address(this));
        chainId = IChaserRegistry(registryAddress).currentChainId();
    }

    function aaveConnection(
        bytes32 operation,
        uint256 amount,
        address poolAddress,
        address assetAddress,
        address marketAddress,
        address poolBroker
    ) internal {
        address trueAsset = assetAddress;
        if (chainId == 11155111) {
            if (marketAddress == address(0)) {
                marketAddress = address(
                    0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
                );
            }
            assetAddress = address(0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357);
        }
        if (chainId == 84532) {
            if (marketAddress == address(0)) {
                marketAddress = address(
                    0x07eA79F68B2B3df564D0A34F8e19D9B1e339814b
                );
            }
        }

        if (operation == hasher("deposit")) {
            emit ExecutionMessage("In deposit");

            ERC20(assetAddress).approve(marketAddress, amount);

            IAavePool(marketAddress).supply(
                assetAddress,
                amount,
                poolBroker,
                0
            );
        }
        if (operation == hasher("withdraw")) {
            emit ExecutionMessage("In withdraw");

            bytes memory encodedFunction = abi.encodeWithSignature(
                "withdraw(address,uint256,address)",
                assetAddress,
                amount,
                poolBroker
            );

            IPoolBroker(poolBroker).withdrawAssets(
                marketAddress,
                encodedFunction
            );

            ERC20(trueAsset).transfer(bridgeLogicAddress, amount);
        }

        // From subgraph market id, how can we get the address of the contract to call functions on?
        //-Instantiate market with address of pool id
        //- on this contract call POOL() to get address of the pool to supply/withdraw
    }

    function compoundConnection(
        bytes32 operation,
        uint256 amount,
        address poolAddress,
        address assetAddress,
        address marketAddress,
        address poolBroker
    ) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
        address trueAsset = assetAddress;
        if (chainId == 11155111) {
            if (marketAddress == address(0)) {
                marketAddress = address(
                    0x2943ac1216979aD8dB76D9147F64E61adc126e96
                );
            }
            assetAddress = address(0x2D5ee574e710219a521449679A4A7f2B43f046ad);
        }
        if (chainId == 84532) {
            if (marketAddress == address(0)) {
                marketAddress = address(
                    0x61490650AbaA31393464C3f34E8B29cd1C44118E
                );
            }
        }

        if (operation == hasher("deposit")) {
            emit ExecutionMessage("In deposit");

            ERC20(assetAddress).approve(marketAddress, amount);

            IComet(marketAddress).supplyTo(poolBroker, assetAddress, amount);
        }
        if (operation == hasher("withdraw")) {
            emit ExecutionMessage("In withdraw");

            bytes memory encodedFunction = abi.encodeWithSignature(
                "withdraw(address,uint256)",
                assetAddress,
                amount
            );

            IPoolBroker(poolBroker).withdrawAssets(
                marketAddress,
                encodedFunction
            );

            ERC20(trueAsset).transfer(bridgeLogicAddress, amount);
        }
    }

    function sparkConnection(
        bytes32 operation,
        uint256 amount,
        address poolAddress,
        address assetAddress,
        address marketAddress,
        address poolBroker
    ) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
    }

    function acrossConnection(
        bytes32 operation,
        uint256 amount,
        address poolAddress,
        address assetAddress,
        address marketAddress,
        address poolBroker
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

        if (_protocolHash == hasher("aave")) {
            // Default to the AAVE pool contract
            if (chainId == 11155111) {
                if (_marketAddress == address(0)) {
                    _marketAddress = address(
                        0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
                    );
                }
                _assetAddress = address(
                    0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357
                );
            }
            if (chainId == 84532) {
                if (_marketAddress == address(0)) {
                    _marketAddress = address(
                        0x07eA79F68B2B3df564D0A34F8e19D9B1e339814b
                    );
                }
            }
            // IN DEVELOPMENT - This contract is preloaded with aave testnet equivalent asset
            // require(ERC20(poolToAsset[_poolAddress]).balanceOf(address(this)) == amount)

            DataTypes.ReserveData memory Reserve = IAavePool(_marketAddress)
                .getReserveData(_assetAddress);
            address aTokenAddress = Reserve.aTokenAddress;

            //-measure integrator's balance of aTokens before depo
            return ERC20(aTokenAddress).balanceOf(brokerAddress);
        }

        if (_protocolHash == hasher("compound")) {
            if (chainId == 11155111) {
                if (_marketAddress == address(0)) {
                    _marketAddress = address(
                        0x2943ac1216979aD8dB76D9147F64E61adc126e96
                    );
                }
            }
            if (chainId == 84532) {
                if (_marketAddress == address(0)) {
                    _marketAddress = address(
                        0x61490650AbaA31393464C3f34E8B29cd1C44118E
                    );
                }
            }

            return IComet(_marketAddress).balanceOf(brokerAddress);
        }
    }

    function hasher(string memory strToHash) public view returns (bytes32) {
        return keccak256(abi.encode(strToHash));
    }

    function routeExternalProtocolInteraction(
        bytes32 protocolHash,
        bytes32 operation,
        uint256 amount,
        address poolAddress,
        address assetAddress,
        address marketAddress
    ) public {
        address poolBroker = IChaserRegistry(registryAddress).getPoolBroker(
            poolAddress,
            assetAddress
        );

        if (protocolHash == hasher("aave")) {
            aaveConnection(
                operation,
                amount,
                poolAddress,
                assetAddress,
                marketAddress,
                poolBroker
            );
        } else if (protocolHash == hasher("compound")) {
            compoundConnection(
                operation,
                amount,
                poolAddress,
                assetAddress,
                marketAddress,
                poolBroker
            );
        } else if (protocolHash == hasher("spark")) {
            sparkConnection(
                operation,
                amount,
                poolAddress,
                assetAddress,
                marketAddress,
                poolBroker
            );
        } else if ((protocolHash == hasher("across"))) {
            acrossConnection(
                operation,
                amount,
                poolAddress,
                assetAddress,
                marketAddress,
                poolBroker
            );
        }
    }
}
