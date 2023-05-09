// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerSupplyToken is TestController {
    function setUp() public override {
        TestController.setUp();
    }

    // supply token
    function testSupplyToken() public {
        controller.supplyToken(WETH_ASSET_ID, 100, false);

        assertEq(IERC20(getSupplyTokenAddress(WETH_ASSET_ID)).balanceOf(address(this)), 100);
    }

    function testCannotSupplyToken_IfAssetIdIsZero() public {
        vm.expectRevert(bytes("A0"));
        controller.supplyToken(0, 100, false);
    }

    function testCannotSupplyToken_IfAssetIdIsNotExisted() public {
        vm.expectRevert(bytes("A0"));
        controller.supplyToken(4, 100, false);
    }
}
