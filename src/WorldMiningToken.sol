// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title World Mining Token
/// @notice Fixed supply of one billion WORLD, with 18 decimals.
/// @dev The immediate deployer receives all tokens. During the launch this is the factory.
/// There are no administrative roles, external mint/burn functions, or upgrade mechanisms.
contract WorldMiningToken is ERC20 {
    /// @notice The entire supply, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("World Mining Token", "WORLD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
