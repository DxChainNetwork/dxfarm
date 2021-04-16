// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/access/Ownable.sol";

contract DxFarmStorage is Ownable {
    /// @dev implementation address
    address public implementation;

    event SetImplementation(address _old, address _new);
}
