// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ArenaGamesToken is ERC20 {
  uint256 public totalSupply_ = 100_000_000 ether;

  constructor() ERC20("Arena Games Platform", "AGP") {
    _mint(_msgSender(), totalSupply_);
  }
}
