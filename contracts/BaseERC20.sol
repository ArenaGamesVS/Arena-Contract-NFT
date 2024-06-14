// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract BaseERC20 is ERC20, AccessControl {
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  constructor(string memory name, string memory symbol, address service) ERC20(name, symbol) {
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(ADMIN_ROLE, _msgSender());
    _grantRole(ADMIN_ROLE, service);
    _grantRole(MINTER_ROLE, _msgSender());
    _grantRole(MINTER_ROLE, service);
  }

  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  function mintBatch(address[] calldata to, uint256[] calldata amount) external onlyRole(MINTER_ROLE) {
    require(to.length == amount.length, "Array size mismatch");
    for (uint256 i = 0; i < to.length; i++) {
      _mint(to[i], amount[i]);
    }
  }
}
