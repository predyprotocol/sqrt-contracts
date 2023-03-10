// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../mocks/MockAttack.sol";

contract TestControllerUniswapCallback is TestController {
    address internal user = vm.addr(uint256(1));

    MockAttack mockAttack;

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user, type(uint128).max);

        vm.prank(user);
        usdc.approve(address(controller), type(uint256).max);

        vm.prank(user);
        controller.supplyToken(STABLE_ASSET_ID, 1e10);

        mockAttack = new MockAttack(address(usdc), address(usdc));
    }

    function testCannotCallMintCallback() public {
        vm.expectRevert(bytes(""));
        mockAttack.callMintCallback(address(controller), 100, 100, "");
    }

    function testCannotCallSwapCallback() public {
        vm.expectRevert(bytes(""));
        mockAttack.callSwapCallback(address(controller), 100, 100, "");
    }
}
