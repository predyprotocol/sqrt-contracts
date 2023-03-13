// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";
import "forge-std/console.sol";

/*
 * https://docs.google.com/spreadsheets/d/101wXPKNGG0vqm7M6Op9WIf1GUKvvdKiCO4riO5D_iFc/edit?usp=sharing
 */
contract TestControllerTradePerp is TestController {
    uint256 vaultId;
    uint256 lpVaultId;

    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user2, type(uint128).max);
        weth.mint(user2, type(uint128).max);

        vm.prank(user2);
        usdc.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        weth.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        controller.supplyToken(1, 1e10);
        vm.prank(user2);
        controller.supplyToken(2, 1e10);

        // create vault
        vaultId = controller.updateMargin(0, 1e10);

        vm.prank(user2);
        lpVaultId = controller.updateMargin(0, 1e10);
    }

    function withdrawAll() internal {
        {
            DataType.Vault memory vault = controller.getVault(vaultId);
            for (uint256 i; i < vault.openPositions.length; i++) {
                Perp.UserStatus memory perpTrade = vault.openPositions[i].perpTrade;

                if (perpTrade.perp.amount != 0 || perpTrade.sqrtPerp.amount != 0) {
                    controller.tradePerp(
                        vaultId, WETH_ASSET_ID, getTradeParams(-perpTrade.perp.amount, -perpTrade.sqrtPerp.amount)
                    );
                }
            }

            controller.updateMargin(vaultId, -controller.getVault(vaultId).margin);
        }

        {
            vm.prank(user2);
            DataType.Vault memory lpVault = controller.getVault(lpVaultId);
            for (uint256 i; i < lpVault.openPositions.length; i++) {
                Perp.UserStatus memory perpTrade = lpVault.openPositions[i].perpTrade;

                if (perpTrade.perp.amount != 0 || perpTrade.sqrtPerp.amount != 0) {
                    TradeLogic.TradeParams memory tradeParams =
                        getTradeParams(-perpTrade.perp.amount, -perpTrade.sqrtPerp.amount);

                    vm.prank(user2);
                    controller.tradePerp(lpVaultId, WETH_ASSET_ID, tradeParams);
                }
            }

            vm.prank(user2);
            int256 margin = controller.getVault(lpVaultId).margin;
            vm.prank(user2);
            controller.updateMargin(lpVaultId, -margin);
        }

        vm.prank(user2);
        controller.withdrawToken(1, 1e18);
        vm.prank(user2);
        controller.withdrawToken(2, 1e18);

        {
            DataType.AssetStatus memory asset = controller.getAsset(1);

            if (asset.accumulatedProtocolRevenue > 0) {
                controller.withdrawProtocolRevenue(1, asset.accumulatedProtocolRevenue);
            }
        }

        {
            DataType.AssetStatus memory asset = controller.getAsset(2);

            if (asset.accumulatedProtocolRevenue > 0) {
                controller.withdrawProtocolRevenue(2, asset.accumulatedProtocolRevenue);
            }
        }

        assertLt(usdc.balanceOf(address(controller)), 100);
        assertLt(weth.balanceOf(address(controller)), 100);
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradeLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    // cannot trade if vaultId is not existed
    function testCannotTrade_IfVaultIdIsNotExisted() public {
        TradeLogic.TradeParams memory tradeParams = getTradeParams(1 * 1e8, 0);

        vm.expectRevert(bytes("V1"));
        controller.tradePerp(0, WETH_ASSET_ID, tradeParams);

        vm.expectRevert(bytes("V1"));
        controller.tradePerp(1000, WETH_ASSET_ID, tradeParams);
    }

    // cannot trade if caller is not vault owner
    function testCannotTrade_IfCallerIsNotVaultOwner() public {
        TradeLogic.TradeParams memory tradeParams = getTradeParams(1 * 1e8, 0);

        vm.prank(user2);
        vm.expectRevert(bytes("V2"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // cannot open position if margin is not safe
    function testCannotTrade_IfVaultIsNotSafe() public {
        controller.updateMargin(vaultId, 1e6 - 1e10);

        TradeLogic.TradeParams memory tradeParams = getTradeParams(-10 * 1e8, 0);

        vm.expectRevert(bytes("NS"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // cannot trade delta because no available supply
    function testCannotOpenLongDelta_IfThereIsNoEnoughSupply() public {
        TradeLogic.TradeParams memory tradeParams = getTradeParams(1e10, 0);

        vm.expectRevert(bytes("S0"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // deadline
    function testCannotTrade_IfTimeIsGreaterThanDeadline() public {
        TradeLogic.TradeParams memory tradeParams = TradeLogic.TradeParams(
            100, 100, getLowerSqrtPrice(WETH_ASSET_ID), getUpperSqrtPrice(WETH_ASSET_ID), block.timestamp - 1, false, ""
        );

        vm.expectRevert(bytes("T1"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // slippage
    function testCannotTrade_IfSlippageIsTooMuch() public {
        TradeLogic.TradeParams memory tradeParams = TradeLogic.TradeParams(
            100, 100, getLowerSqrtPrice(WETH_ASSET_ID), getLowerSqrtPrice(WETH_ASSET_ID), block.timestamp, false, ""
        );

        vm.expectRevert(bytes("T2"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    function testCannotTradePerp_IfAssetIdIsStable() public {
        TradeLogic.TradeParams memory tradeParams = getTradeParams(100, 0);

        vm.expectRevert(bytes("ASSETID"));
        controller.tradePerp(vaultId, STABLE_ASSET_ID, tradeParams);
    }

    function testCannotTradePerp_IfAssetIdIsNotExisted() public {
        TradeLogic.TradeParams memory tradeParams = getTradeParams(100, 0);

        vm.expectRevert(bytes("ASSETID"));
        controller.tradePerp(vaultId, 4, tradeParams);
    }

    // open delta long
    function testOpenLongDelta() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 1e10);

        withdrawAll();
    }

    // close delta long
    function testCloseLongDelta() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(1e6, 0));
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999990000);

        withdrawAll();
    }

    // open delta short
    function testOpenShortDelta() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10000000000);
    }

    // close delta short
    function testCloseShortDelta() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1e6, 0));
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999990000);
    }

    // open sqrt long
    function testOpenLongSqrt() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 1e10);
    }

    // close sqrt long
    function testCloseLongSqrt() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 1e6));
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999990000);
    }

    // open sqrt short
    function testOpenShortSqrt() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 1e6));
        vm.stopPrank();

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 1e10);
    }

    // close sqrt short with full utilization
    function testCloseShortSqrt() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));
        vm.stopPrank();

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -1 * 1e6));

        (uint256 ur,) = controller.getUtilizationRatio(WETH_ASSET_ID);

        assertEq(ur, 1e18);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999990000);
    }

    // cannot open short sqrt if there is no enough liquidity
    function testCannotOpenShortSqrt_IfNoLiquidity() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));
        vm.stopPrank();

        TradeLogic.TradeParams memory tradeParams = getTradeParams(0, -2 * 1e6);

        vm.expectRevert(bytes("P1"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // open gamma short
    function testOpenShortGamma() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1 * 1e6, 1 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 1e10);
    }

    // close gamma short
    function testCloseShortGamma() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1 * 1e6, 1 * 1e6));
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(1 * 1e6, -1 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999990000);
    }

    // pay interest
    function testPayInterest() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(50 * 1e6, 0));

        vm.warp(block.timestamp + 1 days);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-50 * 1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999930000);
    }

    function testPayPremium() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));
        vm.stopPrank();
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -50 * 1e6));

        vm.warp(block.timestamp + 1 weeks);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 50 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999670000);

        withdrawAll();
    }

    function testEarnTradeFee() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 5000 * 1e6));

        for (uint256 i; i < 10; i++) {
            uniswapPool.swap(address(this), false, -21 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");
            uniswapPool.swap(address(this), true, 20 * 1e15, TickMath.MIN_SQRT_RATIO + 1, "");
        }

        vm.warp(block.timestamp + 1 minutes);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -5000 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10098040000);

        withdrawAll();
    }

    // price
    function testLongDeltaAndPriceBecomesHigh() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(10 * 1e6, 0));

        uniswapPool.swap(address(this), false, 10 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 198);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-10 * 1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10000190000);
    }

    function testShortDeltaAndPriceBecomesHigh() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-10 * 1e6, 0));

        uniswapPool.swap(address(this), false, 5 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 99);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(10 * 1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999880000);
    }

    function testLongSqrtAndPriceBecomesHigh() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 10 * 1e6));

        uniswapPool.swap(address(this), false, 10 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 198);
        // 1.00994866723

        assertEq(getSqrtEntryValue(vaultId), -20005004);
        //10094899
        //10099949

        // console.log(11, weth.balanceOf(address(controller)));

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -10 * 1e6));

        // console.log(12, weth.balanceOf(address(controller)));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.openPositions[0].perpTrade.underlying.positionAmount, 0);

        assertEq(vault.margin, 10000180000);

        withdrawAll();
    }

    function testShortSqrtAndPriceBecomesHigh() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 20 * 1e6));
        vm.stopPrank();
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -10 * 1e6));

        // oneForZero
        // USDC -> ETH
        uniswapPool.swap(address(this), false, 6 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 119);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 10 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999870000);
    }

    function testShortGammaAndPriceBecomesHigh() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-10 * 1e6, 10 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 139);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(10 * 1e6, -10 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999990000);
    }

    // after rebalance
    function testSqrtAfterRebalance() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 784);
        // sqrtprice is 1.08155095483

        console.log(10, usdc.balanceOf(address(controller)));
        console.log(10, weth.balanceOf(address(controller)));

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10007890000);

        withdrawAll();
    }

    function testSqrtAfterRebalance2() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        {
            (, int24 currentTick,,,,,) = uniswapPool.slot0();

            assertEq(currentTick, 0);
            // sqrtprice is 1
        }

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        {
            (, int24 currentTick,,,,,) = uniswapPool.slot0();

            assertEq(currentTick, 784);
            // sqrtprice is 1.03997642032
        }

        assertEq(getSqrtEntryValue(vaultId), -200050027);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 0));

        assertEq(getSqrtEntryValue(vaultId), -200050027);

        DataType.TradeResult memory tradeResult =
            controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        // trade price is 207995284
        //
        // 207995284 - 200050029

        assertEq(tradeResult.payoff.sqrtPayoff, 7990000);

        withdrawAll();
    }

    function getSqrtEntryValue(uint256 _vaultId) internal view returns (int256) {
        DataType.Vault memory vault = controller.getVault(_vaultId);
        DataType.UserStatus memory userStatus = vault.openPositions[0];

        return userStatus.perpTrade.sqrtPerp.entryValue; //  + userStatus.perpTrade.sqrtPerp.rebalanceEntryValue;
    }

    function testGammaAfterRebalance() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
        //address(this), true, 12 * 1e15, TickMath.MIN_SQRT_RATIO + 1, ""

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 784);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999830000);

        withdrawAll();
    }

    function testSqrtOutOfRange() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1352);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10013910000);

        withdrawAll();
    }

    function testGammaOutOfRange() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1352);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999530000);

        withdrawAll();
    }

    // sqrt short and rebalance
    function testSqrtShortOutOfRange() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 110 * 1e6));
        vm.stopPrank();
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -100 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1352);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9985900000);

        withdrawAll();
    }

    // gamma long and rebalance
    function testGammaLongOutOfRange() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 110 * 1e6));
        vm.stopPrank();
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1352);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10000480000);

        withdrawAll();
    }

    function testVaultValueAfterRebalance() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 784);

        vm.warp(block.timestamp + 1 hours);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        DataType.VaultStatusResult memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.vaultValue, 9999838139);

        withdrawAll();
    }

    function testCloseShortSqrtAndLongPerpAfterRebalance() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));
        vm.stopPrank();

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));
        vm.stopPrank();

        DataType.TradeResult memory tradeResult =
            controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(1e5, -1 * 1e6));

        assertEq(tradeResult.minDeposit, 1000000);

        (uint256 ur,) = controller.getUtilizationRatio(WETH_ASSET_ID);

        assertEq(ur, 5 * 1e17);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999990000);
    }
}
