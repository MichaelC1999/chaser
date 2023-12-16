// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {PoolControl} from "./PoolControl.sol";
import {Registry} from "./Registry.sol";
import {ArbitrationContract} from "./ArbitrationContract.sol";

interface IChaserManager {
    function createNewPool(
        address poolAsset,
        uint amount,
        string memory strategyURI,
        string memory poolName
    ) external;

    function viewRegistryAddress() external view returns (address);
}

contract ChaserManager {
    //Should this inherit a factory contract?

    //Addresses managed in registry
    //Pool creation function
    //Each pool is a new contract
    // Deposit functionality pointing to a pool
    // Assertion functionality to be called by a user from Pool contract
    // Bridging functionality to be called by a pool contract for secuity purposes. Access control in spokes

    Registry public registry;
    ArbitrationContract public arbitrationContract;

    constructor(uint256 chainId) {
        registry = new Registry();
        arbitrationContract = new ArbitrationContract(
            address(registry),
            chainId
        );
    }

    function createNewPool(
        address poolAsset,
        uint amount,
        string memory strategyURI,
        string memory poolName
    ) public {
        address initialDepositor = msg.sender;

        PoolControl pool = new PoolControl(
            initialDepositor,
            poolAsset,
            amount,
            strategyURI,
            poolName,
            42161
        );
        address poolAddress = address(pool);
        registry.addPoolEnabled(poolAddress);
    }

    function viewRegistryAddress() external view returns (address) {
        return address(registry);
    }
}
