// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice Mock of ERC20 contract
 */
contract MockERC20 is ERC20 {
    uint8 _decimals;

    constructor(string memory _name, string memory _symbol, uint8 __decimals) ERC20(_name, _symbol) {
        _decimals = __decimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
