// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/ISupplyToken.sol";

contract SupplyToken is ERC20, ISupplyToken {
    address immutable controller;

    modifier onlyController() {
        require(controller == msg.sender, "ST0");
        _;
    }

    constructor(address _controller, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        controller = _controller;
    }

    function mint(address account, uint256 amount) external virtual override onlyController {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external virtual override onlyController {
        _burn(account, amount);
    }
}
