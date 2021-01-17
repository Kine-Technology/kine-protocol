pragma solidity ^0.5.16;

import "./ERC20.sol";

/**
 * @title KineUSD
 * @notice Kine is the platform token of Kine system.
 * @author Kine
 */
contract Kine is ERC20 {
    /// @notice Kine token name
    string public name;
    /// @notice Kine token symbol
    string public symbol;
    /// @notice Kine token decimals
    uint8 public decimals;

    constructor (string memory name_, string memory symbol_, uint8 decimals_, uint totalSupply) public {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        _mint(msg.sender, totalSupply);
    }
}