// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PoolControl} from "./PoolControl.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IArbitrationContract} from "./interfaces/IArbitrationContract.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

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
        string memory poolName,
        uint256 proposalRewardUSDC,
        uint256 proposalBondUSDC,
        uint256 livenessLevel
    ) external {
        IERC20 usdc = IERC20(registry.addressUSDC(currentChainId));
        require(
            usdc.balanceOf(msg.sender) >= proposalRewardUSDC,
            "Not enough USDC for pre-depositing reward"
        );
        require(
            usdc.allowance(msg.sender, address(this)) >= proposalRewardUSDC,
            "Need to approve USDC for pre-depositing reward"
        );
        address arbitrationAddress = registry.arbitrationContract();

        PoolControl pool = new PoolControl(
            msg.sender,
            poolAsset,
            strategyIndex,
            poolName,
            currentChainId,
            proposalRewardUSDC,
            address(registry),
            poolCalculationsAddress,
            arbitrationAddress
        );
        address poolAddress = address(pool);
        IArbitrationContract(arbitrationAddress).setArbitrationConfigs(
            poolAddress,
            proposalBondUSDC,
            livenessLevel
        );
        registry.enablePool(poolAddress);
        usdc.transferFrom(msg.sender, poolAddress, proposalRewardUSDC);
        emit PoolCreated(poolAddress);
    }
}
