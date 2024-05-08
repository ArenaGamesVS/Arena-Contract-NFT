//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./Collection.sol";
import "../../interfaces/IAdminContract.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract CollectionFactory {
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
  bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

  mapping (bytes32 => string) public roles;
  address public adminContract;

  event CollectionCreated(address indexed collection, string slug);
  event AdminContractChanged(address newContract);

  modifier onlyRole(bytes32 role) {
    require(
      IAdminContract(adminContract).hasRole(role, msg.sender),
      string(
        abi.encodePacked(
          "AccessControl: account ",
          Strings.toHexString(uint160(msg.sender), 20),
          " is missing role ",
          roles[role]
        )
      )
    );
    _;
  }

  constructor(address _adminContract) {
    adminContract = _adminContract;
    roles[ADMIN_ROLE] = "ADMIN_ROLE";
    roles[CREATOR_ROLE] = "CREATOR_ROLE";
  }

  // CREATOR FUNCTIONS

  function createCollection(
    string calldata name,
    string calldata symbol,
    string calldata slug_,
    address signer_,
    address _gallery
  ) external onlyRole(CREATOR_ROLE) returns (address collection) {
    collection = address(new Collection(msg.sender, name, symbol, slug_, signer_, _gallery));
    emit CollectionCreated(collection, slug_);
  }

  function setAdminContract(address _adminContract) external onlyRole(ADMIN_ROLE) {
    require(IAdminContract(_adminContract).isAdminContract(), "Wrong contract!");
    adminContract = _adminContract;
    emit AdminContractChanged(adminContract);
  }
}
