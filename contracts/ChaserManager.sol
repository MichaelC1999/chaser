// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PoolControl} from "./PoolControl.sol";
import {Registry} from "./Registry.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface IChaserManager {
    function createNewPool(
        address poolAsset,
        uint amount,
        uint256 strategyIndex,
        string memory poolName
    ) external;
}

contract ChaserManager is OwnableUpgradeable {
    IChaserRegistry public registry;

    uint256 currentChainId;

    address poolCalculationsAddress;

    event PoolCreated(address indexed poolAddress);

    function initialize(uint256 _chainId) public initializer {
        __Ownable_init();
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
    ) external {
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
        registry.enablePool(poolAddress);
        emit PoolCreated(poolAddress);
    }
}
