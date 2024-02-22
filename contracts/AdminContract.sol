// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

contract AdminContract is AccessControlEnumerableUpgradeable{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    constructor() {}

    function initialize() public initializer {
        __AccessControlEnumerable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());
        _setRoleAdmin(CREATOR_ROLE, ADMIN_ROLE);
    }

    function isAdminContract() external pure returns (bool) {
        return true;
    }
}