// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Integrations {
    function aaveConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
        //-Instantiate market with address of pool id
        //- on this contract call POOL() to get address of the pool to supply/withdraw
    }

    function compoundConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
        //- CompoundV3 subgraph market id is 40 bytes long, joining the market address bytes to the asset address bytes
        //-Take the first 20 bytes to get address to make spply/withdraw method calls
    }

    function sparkConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
    }

    function acrossConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
    }

    function routeExternalProtocolInteraction(
        bytes32 protocolHash,
        bytes32 operation
    ) public {
        if (protocolHash == keccak256(abi.encode("aave"))) {
            aaveConnection(operation);
        } else if (protocolHash == keccak256(abi.encode("compound"))) {
            compoundConnection(operation);
        } else if (protocolHash == keccak256(abi.encode("spark"))) {
            sparkConnection(operation);
        } else if ((protocolHash == keccak256(abi.encode("across")))) {
            acrossConnection(operation);
        }
    }
}
