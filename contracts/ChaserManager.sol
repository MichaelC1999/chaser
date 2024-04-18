// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

import {PoolControl} from "./PoolControl.sol";
import {Registry} from "./Registry.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";

interface IChaserManager {
    function createNewPool(
        address poolAsset,
        uint amount,
        uint256 strategyIndex,
        string memory poolName
    ) external;
}

contract ChaserManager is OwnerIsCreator {
    IChaserRegistry public registry;

    uint256 currentChainId;

    address poolCalculationsAddress;

    event PoolCreated(address indexed poolAddress);

    constructor(uint256 _chainId) {
        currentChainId = _chainId;
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
        uint256 strategyIndex,
        string memory poolName
    ) public {
        address initialDepositor = msg.sender;

        PoolControl pool = new PoolControl(
            initialDepositor,
            poolAsset,
            strategyIndex,
            poolName,
            currentChainId,
            address(registry),
            poolCalculationsAddress
        );
        address poolAddress = address(pool);
        registry.addPoolEnabled(poolAddress);
        emit PoolCreated(poolAddress);
    }
}
