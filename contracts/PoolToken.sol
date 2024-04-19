// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract PoolToken is ERC20 {
    address public poolAddress;

    constructor(
        address initialDepositor,
        uint256 initialSupply,
        string memory poolId
    ) ERC20(string.concat("Chaser-", poolId), string.concat("PVT-", poolId)) {
        poolAddress = address(msg.sender);
        // Take the rounded down base 10 log of total supplied tokens by user
        // Make the initial supply 10 ^ (18 + base10 log)
        uint256 supplyFactor = (Math.log10(initialSupply));

        uint256 initialTokensToDepositor = 10 ** supplyFactor;

        _mint(initialDepositor, initialTokensToDepositor);
    }

    function mint(address recipient, uint256 amount) external {
        require(msg.sender == poolAddress, "Only pool may call mint");
        _mint(recipient, amount);
    }

    function burn(address holder, uint256 amount) external {
        require(msg.sender == poolAddress, "Only pool may call burn");
        _burn(holder, amount);
    }
}
