// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
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

    // mapping(address => uint256) public poolToOutputTokens; // IMPORTANT - This will be needed for RESCUE_ASSETS() function
    // mapping(address => uint256) public poolToPositionPortion; // This records what portions of deposits pertain to a certain pool, if a market has investment from multiple pools
    // uint256 public totalPositionPortion; // Total amount of portion in a given market

    address public bridgeLogicAddress;
    address public registryAddress;
    event ExecutionMessage(string);

    constructor(address _bridgeLogicAddress, address _registryAddress) {
        bridgeLogicAddress = _bridgeLogicAddress;
        registryAddress = _registryAddress;
        IChaserRegistry(registryAddress).addIntegrator(address(this));
    }

    function aaveConnection(
        bytes32 operation,
        uint256 amount,
        address poolAddress,
        address assetAddress,
        address marketAddress,
        address poolBroker
    ) internal {
        if (operation == hasher("deposit")) {
            emit ExecutionMessage("In deposit");
            //Supply
            // transferFrom bridgeLogic to this contract

            //**********************************************************************************************
            // Default to the AAVE pool contract
            if (marketAddress == address(0)) {
                marketAddress = address(
                    0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
                );
            }

            // measure ratio of assets in deposit to current position balance. Call aave position balance function
            // uint256 currentPositionBalance = getPositionBalance(marketAddress);
            // Use this ratio to calculate pos token amount. calculatePortion()
            //Add value to poolToPositionPortion mapping. Add to positionPortion total

            // IN DEVELOPMENT - This contract is preloaded with aave testnet equivalent asset
            // require(ERC20(poolToAsset[_poolAddress]).balanceOf(address(this)) == amount)
            assetAddress = address(0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357);

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
            //Withdraw
            // Set  mapping pool => aTokens as 0
            // Call withdraw(address asset, uint256 amount, address to) on the aave pool
            if (marketAddress == address(0)) {
                marketAddress = address(
                    0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
                );
            }
            // IN DEVELOPMENT - This contract is preloaded with aave testnet equivalent asset

            bytes memory encodedFunction = abi.encodeWithSignature(
                "withdraw(address,uint256,address)",
                address(0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357),
                amount,
                poolBroker
            );

            IPoolBroker(poolBroker).withdrawAssets(
                marketAddress,
                encodedFunction
            );

            ERC20(assetAddress).transfer(bridgeLogicAddress, amount);
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
        //- CompoundV3 subgraph market id is 40 bytes long, joining the market address bytes to the asset address bytes
        //-Take the first 20 bytes to get address to make spply/withdraw method calls
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
            if (_marketAddress == address(0)) {
                _marketAddress = address(
                    0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
                );
            }
            // IN DEVELOPMENT - This contract is preloaded with aave testnet equivalent asset
            // require(ERC20(poolToAsset[_poolAddress]).balanceOf(address(this)) == amount)
            _assetAddress = address(0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357);

            DataTypes.ReserveData memory Reserve = IAavePool(_marketAddress)
                .getReserveData(_assetAddress);
            address aTokenAddress = Reserve.aTokenAddress;

            //-measure integrator's balance of aTokens before depo
            return ERC20(aTokenAddress).balanceOf(brokerAddress);
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
