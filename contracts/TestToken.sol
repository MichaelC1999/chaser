// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./interfaces/IERC20.sol"; // Ensure the path to IERC20 is correctly specified

contract TestToken is IERC20 {
    string public name = "TestToken";
    string public symbol = "BET";
    uint8 public decimals = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    constructor() {
        _mint(msg.sender, 1_000_000 * 10 ** uint256(decimals)); // 1 million tokens
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address to,
        uint256 value
    ) external override returns (bool) {
        require(to != address(0), "Invalid address");
        require(_balances[msg.sender] >= value, "Insufficient balance");

        _balances[msg.sender] -= value;
        _balances[to] += value;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 value
    ) external override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        require(to != address(0), "Invalid address");
        require(_balances[from] >= value, "Insufficient balance");
        require(_allowances[from][msg.sender] >= value, "Allowance exceeded");

        _balances[from] -= value;
        _balances[to] += value;
        _allowances[from][msg.sender] -= value;

        emit Transfer(from, to, value);
        return true;
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "Invalid address");

        _totalSupply += value;
        _balances[account] += value;
        emit Transfer(address(0), account, value);
    }
}
