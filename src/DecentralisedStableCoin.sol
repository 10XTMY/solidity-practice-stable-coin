// SPDX-License-Identifier: MIT

// Layout of Contract:
// pragma statements
// imports
// interfaces
// libraries
// contracts
// Errors

// inside each contract, library, or interface:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzepplin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzepplin/contracts/access/Ownable.sol";

/*
 * @title DecentralisedStableCoin
 * @author 10XTMY
 * Collateral: Exogenous (ETH, BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This contract is to be managed by DSCEngine.
 * This contract is the ERC20 implementation of the stability system.
 *
 */

// burning helps maintain the peg
// this token is 100% governed by the DSCEngine
// so we make it ownable, using only owner modifiers
contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__ZeroSenderBalance();
    error DecentralisedStableCoin__BurnAmountExceedsBalance();
    error DecentralisedStableCoin__MintToZeroAddress();
    error DecentralisedStableCoin__ZeroMintAmount();

    constructor() ERC20("DecentralisedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin__ZeroSenderBalance();
        }
        if (balance < _amount) {
            revert DecentralisedStableCoin__BurnAmountExceedsBalance();
        }
        // use the super class function from ERC20Burnable
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__MintToZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin__ZeroMintAmount();
        }
        _mint(_to, _amount);
        return true;
    }
}
