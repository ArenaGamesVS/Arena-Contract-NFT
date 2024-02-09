//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

library UniqueArray {
  // Add a value to an array if it doesn't already exist in the array
  function addUnique(address[] storage array, address value) internal {
    // Check if the value already exists in the array
    for (uint i = 0; i < array.length; i++) {
      if (array[i] == value) {
        return;
      }
    }
    // If the value does not exist, add it to the array
    array.push(value);
  }
}
