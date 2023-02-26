// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract TestControllerSupplyToken is TestController {
    function setUp() public override {
        TestController.setUp();
    }

    // supply token
    function testSupplyToken() public {
        controller.supplyToken(WETH_ASSET_ID, 100);

        assertEq(IERC20(getSupplyTokenAddress(WETH_ASSET_ID)).balanceOf(address(this)), 100);
    }
    // supply token if utilization is full
} // cannot supply token if user has no balance
