// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerReallocate is TestController {
    uint256 vaultId1;
    uint256 vaultId2;

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
        vaultId1 = controller.updateMargin(PAIR_GROUP_ID, 1e10);

        controller.tradePerp(vaultId1, WETH_ASSET_ID, getTradeParams(-20 * 1e6, 100 * 1e6));
        vm.stopPrank();

        vm.prank(user2);
        vaultId2 = controller.updateMargin(PAIR_GROUP_ID, 1e10);

        uniswapPool.swap(address(this), false, 3 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradePerpLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    function testReallocate() public {
        (bool isReallicated, int256 profit) = controller.reallocate(WETH_ASSET_ID);

        assertTrue(isReallicated);
        assertEq(profit, 0);

        {
            DataType.PairStatus memory pairBefore = controller.getAsset(WETH_ASSET_ID);
            assertEq(pairBefore.sqrtAssetStatus.lastRebalanceTotalSquartAmount, 100 * 1e6);
        }

        vm.startPrank(user1);
        controller.tradePerp(vaultId1, WETH_ASSET_ID, getTradeParams(10 * 1e6, -50 * 1e6));
        vm.stopPrank();

        {
            DataType.PairStatus memory pairAfter = controller.getAsset(WETH_ASSET_ID);
            assertEq(pairAfter.sqrtAssetStatus.lastRebalanceTotalSquartAmount, 0);
        }
    }

    function testCannotReallocateStableAsset() public {
        vm.expectRevert(bytes("A0"));
        controller.reallocate(0);
    }

    function testCannotReallocateInvalidAssetId() public {
        vm.expectRevert(bytes("A0"));
        controller.reallocate(4);
    }

    // trade 1->reallocation->trade 2->trade 1->trade 2
    function testTradeAfterReallocation() public {
        uniswapPool.swap(address(this), false, 2 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        checkTick(975);

        controller.reallocate(WETH_ASSET_ID);

        vm.startPrank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        {
            DataType.Vault memory vault1Before = controller.getVault(vaultId1);
            DataType.Vault memory vault2Before = controller.getVault(vaultId2);

            assertEq(vault1Before.openPositions[0].lastNumRebalance, 0);
            assertEq(vault2Before.openPositions[0].lastNumRebalance, 1);
        }

        vm.startPrank(user1);
        controller.tradePerp(vaultId1, WETH_ASSET_ID, getTradeParams(10 * 1e6, -50 * 1e6));
        vm.stopPrank();

        vm.startPrank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, getTradeParams(10 * 1e6, -50 * 1e6));
        vm.stopPrank();

        {
            DataType.Vault memory vault1After = controller.getVault(vaultId1);
            DataType.Vault memory vault2After = controller.getVault(vaultId2);

            assertEq(vault1After.openPositions[0].lastNumRebalance, 1);
            assertEq(vault2After.openPositions[0].lastNumRebalance, 1);
        }
    }

    // trade 1->trade 2->reallocation->trade 1->trade 2
    function testOneSettleAndOneLeft() public {
        vm.startPrank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));
        vm.stopPrank();

        uniswapPool.swap(address(this), false, 2 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        checkTick(975);

        controller.reallocate(WETH_ASSET_ID);

        vm.warp(block.timestamp + 1 hours);

        vm.startPrank(user1);
        controller.tradePerp(vaultId1, WETH_ASSET_ID, getTradeParams(10 * 1e6, -50 * 1e6));
        vm.stopPrank();

        {
            DataType.PairStatus memory pairBefore = controller.getAsset(WETH_ASSET_ID);
            assertEq(pairBefore.sqrtAssetStatus.lastRebalanceTotalSquartAmount, 100 * 1e6);
        }

        vm.startPrank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, getTradeParams(10 * 1e6, -50 * 1e6));
        vm.stopPrank();

        {
            DataType.PairStatus memory pairAfter = controller.getAsset(WETH_ASSET_ID);
            assertEq(pairAfter.sqrtAssetStatus.lastRebalanceTotalSquartAmount, 0);
        }
    }
}
