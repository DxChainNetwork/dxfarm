// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract DxVault is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // DxChain Token
    address public DX;

    // Set of address that are approved suppliers
    EnumerableSet.AddressSet private Suppliers;

    event Supply(address to, uint256 amount);

    constructor(address dx) public {
        require(dx != address(0), "zero address");
        DX = dx;
        Suppliers.add(Ownable(DX).owner());
    }

    /**
     * @dev add new supplier
     */
    function addSupplier(address supplier) public onlyOwner {
        require(supplier != address(0), "supplier address zero");
        Suppliers.add(supplier);
    }

    /**
     * @dev remove exist supplier
     */
    function removeSupplier(address supplier) public onlyOwner {
        require(supplier != address(0), "supplier address zero");
        Suppliers.remove(supplier);
    }

    /**
     * @dev check supplier isSupplier
     */
    function isSupplier(address supplier) public view returns (bool) {
        return Suppliers.contains(supplier);
    }

    /**
     * @dev supply DXs from vault to msg.sender(supplier)
     * @param amount amount of supply
     */
    function supply(uint256 amount) external {
        require(isSupplier(msg.sender), "not supplier");
        require(
            IERC20(DX).balanceOf(address(this)) >= amount,
            "insufficient Vault balance!"
        );

        IERC20(DX).transfer(msg.sender, amount);

        emit Supply(msg.sender, amount);
    }
}
