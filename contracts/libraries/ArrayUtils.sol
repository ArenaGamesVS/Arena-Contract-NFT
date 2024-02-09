// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ArrayUtils {
  /**
   * @dev Removes an element from a dynamic array at a specified index.
   * The last element of the array is moved to the position of the removed element,
   * and the array length is decreased by 1.
   * @param array The dynamic array to modify.
   * @param index The index of the element to remove.
   * @return The removed element.
   */
  function removeAtIndex(uint256[] storage array, uint256 index) internal returns (uint256) {
    require(index < array.length, "Index out of bounds");
    uint256 removed = array[index];
    uint256 last = array[array.length - 1];
    array[index] = last;
    array.pop();
    return removed;
  }
}
