// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {PoolControl} from "./PoolControl.sol";
import {ChaserRouter} from "./ChaserRouter.sol";
import {Registry} from "./Registry.sol";
import {ArbitrationContract} from "./ArbitrationContract.sol";

interface IChaserManager {
    function createNewPool(
        address poolAsset,
        uint amount,
        string memory strategyURI,
        string memory poolName
    ) external;

    function initializeContractConnections(address) external;

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

    uint256 LOCAL_CHAIN;

    event PoolCreated(address indexed poolAddress);

    constructor(uint256 _chainId) {
        LOCAL_CHAIN = _chainId;
        registry = new Registry(_chainId, _chainId);
        // arbitrationContract = new ArbitrationContract(
        //     address(registry),
        //     _chainId
        // );
        // registry.addArbitrationContract(address(arbitrationContract));
    }

    function createNewPool(
        address poolAsset,
        string memory strategyURI,
        string memory poolName
    ) public {
        address initialDepositor = msg.sender;

        PoolControl pool = new PoolControl(
            initialDepositor,
            poolAsset,
            strategyURI,
            poolName,
            LOCAL_CHAIN
        );
        address poolAddress = address(pool);
        registry.addPoolEnabled(poolAddress);
        emit PoolCreated(poolAddress);
    }

    function initializeContractConnections(address _poolAddress) external {
        PoolControl(_poolAddress).initializeContractConnections(
            address(registry)
        );
    }

    function viewRegistryAddress() external view returns (address) {
        return address(registry);
    }
}
