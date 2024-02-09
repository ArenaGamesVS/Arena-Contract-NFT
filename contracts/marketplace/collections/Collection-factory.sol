//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./Collection.sol";

contract CollectionFactory {
  event CollectionCreated(address indexed collection, string slug);

  // CREATOR FUNCTIONS

  function createCollection(
    string calldata name,
    string calldata symbol,
    string calldata slug_,
    address signer_,
    address _gallery
  ) external returns (address collection) {
    collection = address(new Collection(msg.sender, name, symbol, slug_, signer_, _gallery));
    emit CollectionCreated(collection, slug_);
  }
}
