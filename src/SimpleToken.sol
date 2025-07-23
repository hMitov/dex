// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title Simple ERC20 Token for Development and Testing
/// @notice Minimal ERC20 implementation with unrestricted minting for dev purposes
contract SimpleToken is IERC20 {
    /// @notice Token name
    string public name;

    /// @notice Token symbol
    string public symbol;

    /// @notice Token decimals (default 18)
    uint8 public decimals = 18;

    /// @dev Total supply of tokens
    uint256 private _totalSupply;

    /// @dev Mapping of account balances
    mapping(address => uint256) private balances;

    /// @dev Mapping of account allowances
    mapping(address => mapping(address => uint256)) private allowances;

    /// @notice Constructs the token with given name and symbol
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /// @notice Returns total token supply
    /// @return The total number of tokens in existence
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /// @notice Returns the balance of a given account
    /// @param account The address to query the balance for
    /// @return The balance of tokens owned by `account`
    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    /// @notice Transfers tokens to a recipient
    /// @param recipient The address to transfer tokens to
    /// @param amount The number of tokens to transfer
    /// @return True if transfer succeeded
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        balances[recipient] += amount;

        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Approves a spender to spend tokens on caller's behalf
    /// @param spender The address allowed to spend tokens
    /// @param amount The amount of tokens approved for spending
    /// @return True if approval succeeded
    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers tokens from sender to recipient using allowance mechanism
    /// @param sender The address to send tokens from
    /// @param recipient The address to send tokens to
    /// @param amount The number of tokens to transfer
    /// @return True if transfer succeeded
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(balances[sender] >= amount, "Insufficient balance");
        require(allowances[sender][msg.sender] >= amount, "Allowance exceeded");

        balances[sender] -= amount;
        balances[recipient] += amount;
        allowances[sender][msg.sender] -= amount;

        emit Transfer(sender, recipient, amount);
        return true;
    }

    /// @notice Returns the remaining allowance a spender has from an owner
    /// @param owner The owner of the tokens
    /// @param spender The spender allowed to use tokens
    /// @return Remaining allowance amount
    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    /// @notice Mints new tokens to a specified address
    /// @param to The address to receive minted tokens
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        _totalSupply += amount;

        emit Transfer(address(0), to, amount);
    }
}
