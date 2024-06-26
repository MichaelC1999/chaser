// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract ChaserTreasury is OwnableUpgradeable {
    IChaserRegistry public registry;

    mapping(address => uint256) public poolAddressToCumulativeProtocolFees;
    mapping(address => uint256) public poolToRewardDebt;
    address managerAddress;
    uint256 currentChainId;

    function initialize(uint256 _chainId) public initializer {
        __Ownable_init();
        currentChainId = _chainId;
    }

    function separateProtocolFeeAndReward(
        uint256 _rewardAmountInAsset,
        uint256 _protocolFees,
        address _poolAddress,
        address _poolAsset
    ) external {
        address addressUSDC = registry.addressUSDC(currentChainId);
        uint256 rewardUSDC = IPoolControl(_poolAddress).proposalRewardUSDC();
        poolAddressToCumulativeProtocolFees[_poolAddress] += _protocolFees;
        // Get proposalRewardUSDC and asset from poolControl
        // swap asset with inAmount being _rewardAmountInAsset, output amount being the reward in USDC
        // The INPUT amount should be fixed as that is waht is provided in bridge.
        // If the output amount is less than the reward on the pool pass this difference to arbitration
        // Send the output token complete amount to arbitration

        uint256 usdcReceived = _swapTreasuryAsset(
            _rewardAmountInAsset,
            rewardUSDC,
            _poolAsset,
            addressUSDC
        );

        IERC20(addressUSDC).transfer(_poolAddress, rewardUSDC);

        uint256 debt = 0;
        if (rewardUSDC > usdcReceived) {
            debt = rewardUSDC - usdcReceived;
        }
        poolToRewardDebt[_poolAddress] = (debt);
    }

    function _swapTreasuryAsset(
        uint256 inAmount,
        uint256 outAmount,
        address fromAsset,
        address toAsset
    ) internal returns (uint256) {
        ISwapRouter uniswapRouter = ISwapRouter(
            registry.uniswapRouter(currentChainId)
        );
        if (address(uniswapRouter) == address(0)) {
            return outAmount;
        }
        // inAmount is the maximum amount of input tokens used for the swap to the fixed amount of output tokens
        //IMPORTANT - FOR TESTNETS, AVOID ATTEMPTING THE SWAP AND JUST RETURN outAmount
        require(
            IERC20(fromAsset).approve(address(uniswapRouter), inAmount),
            "Approve failed"
        );

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: fromAsset,
                tokenOut: toAsset,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp + 15, // 15 seconds deadline
                amountIn: inAmount,
                amountOutMinimum: 50,
                sqrtPriceLimitX96: 0
            });

        uint256 outputUSDC = outAmount;
        try uniswapRouter.exactInputSingle(params) returns (
            uint256 swapOutput
        ) {
            outputUSDC = swapOutput;
        } catch {}
        return outputUSDC;
    }

    function swapTreasuryAsset(
        uint256 inAmount,
        uint256 outAmount,
        address fromAsset,
        address toAsset
    ) external onlyOwner returns (uint256) {
        return _swapTreasuryAsset(inAmount, outAmount, fromAsset, toAsset);
    }

    function protocolWithdraw(
        uint256 amount,
        address asset
    ) external onlyOwner {
        require(IERC20(asset).transfer(owner(), amount), "Transfer failed");
    }

    function addRegistry(address _registryAddress) external onlyOwner {
        registry = IChaserRegistry(_registryAddress);
    }
}
