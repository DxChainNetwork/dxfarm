// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IDxVault {
    function supply(uint256 amount) external;

    function DX() external returns (address);
}
