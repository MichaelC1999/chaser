// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

import {PoolControl} from "./PoolControl.sol";
import {Registry} from "./Registry.sol";
import {ArbitrationContract} from "./ArbitrationContract.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";

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

contract ChaserManager is OwnerIsCreator {
    //Should this inherit a factory contract?

    //Addresses managed in registry
    //Pool creation function
    //Each pool is a new contract
    // Deposit functionality pointing to a pool
    // Assertion functionality to be called by a user from Pool contract
    // Bridging functionality to be called by a pool contract for secuity purposes. Access control in spokes

    IChaserRegistry public registry;
    ArbitrationContract public arbitrationContract;

    uint256 currentChainId;

    address poolCalculationsAddress;

    event PoolCreated(address indexed poolAddress);

    constructor(uint256 _chainId) {
        currentChainId = _chainId;
        // arbitrationContract = new ArbitrationContract(
        //     address(registry),
        //     _chainId
        // );
        // registry.addArbitrationContract(address(arbitrationContract));
    }

    function addRegistry(address registryAddress) external onlyOwner {
        registry = IChaserRegistry(registryAddress);
    }

    function addPoolCalculationsAddress(
        address _poolCalculationsAddress
    ) external onlyOwner {
        poolCalculationsAddress = _poolCalculationsAddress;
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
            currentChainId,
            address(registry),
            poolCalculationsAddress
        );
        // pool.initializeContractConnections(address(registry));
        address poolAddress = address(pool);
        registry.addPoolEnabled(poolAddress);
        emit PoolCreated(poolAddress);
    }

    // function initializeContractConnections(address _poolAddress) external {
    //     PoolControl(_poolAddress).initializeContractConnections(
    //         address(registry)
    //     );
    // }

    function viewRegistryAddress() external view returns (address) {
        return address(registry);
    }
}
