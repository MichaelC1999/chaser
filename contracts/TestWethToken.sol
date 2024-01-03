// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestWETHToken is ERC20 {
    constructor() ERC20("Wrapped ETHER", "WETH") {
        _mint(msg.sender, 1000 ether);
    }
}
