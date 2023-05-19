// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerReallocate is TestController {
    uint256 vaultId1;

    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user1, type(uint128).max);
        usdc.mint(user2, type(uint128).max);
        weth.mint(user2, type(uint128).max);
        wbtc.mint(user2, type(uint128).max);

        vm.prank(user1);
        usdc.approve(address(controller), type(uint256).max);

        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        wbtc.approve(address(controller), type(uint256).max);

        controller.supplyToken(WETH_ASSET_ID, 1e10, true);
        controller.supplyToken(WETH_ASSET_ID, 1e10, false);
        controller.supplyToken(WBTC_ASSET_ID, 1e10, true);
        controller.supplyToken(WBTC_ASSET_ID, 1e10, false);
        vm.stopPrank();

        // create vault
        vm.startPrank(user1);
        vaultId1 = controller.updateMargin(1e10);

        controller.tradePerp(vaultId1, WETH_ASSET_ID, getTradeParams(-20 * 1e6, 100 * 1e6));
        vm.stopPrank();

        uniswapPool.swap(address(this), false, 3 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradeLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    function testReallocate() public {
        (bool isReallicated, int256 profit) = controller.reallocate(WETH_ASSET_ID);

        assertTrue(isReallicated);
        assertEq(profit, 0);
    }

    function testCannotReallocateStableAsset() public {
        vm.expectRevert(bytes("A0"));
        controller.reallocate(0);
    }

    function testCannotReallocateInvalidAssetId() public {
        vm.expectRevert(bytes("A0"));
        controller.reallocate(4);
    }
}
