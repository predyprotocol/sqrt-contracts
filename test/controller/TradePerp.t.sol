// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";
import "../../src/Reader.sol";
import "forge-std/console.sol";

/*
 * https://docs.google.com/spreadsheets/d/101wXPKNGG0vqm7M6Op9WIf1GUKvvdKiCO4riO5D_iFc/edit?usp=sharing
 */
contract TestControllerTradePerp is TestController {
    Reader reader;
    uint256 vaultId;
    uint256 lpVaultId;

    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user2, type(uint128).max);
        weth.mint(user2, type(uint128).max);

        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);

        controller.supplyToken(WETH_ASSET_ID, 1e10, true);
        controller.supplyToken(WETH_ASSET_ID, 1e10, false);
        vm.stopPrank();

        // create vault
        vaultId = controller.updateMargin(1e10, 0);

        vm.prank(user2);
        lpVaultId = controller.updateMargin(1e10, 0);

        reader = new Reader(controller);
    }

    function withdrawAll() internal {
        vm.warp(block.timestamp + 1 hours);

        {
            DataType.Vault memory vault = controller.getVault(vaultId);
            for (uint256 i; i < vault.openPositions.length; i++) {
                Perp.UserStatus memory perpTrade = vault.openPositions[i];

                if (perpTrade.perp.amount != 0 || perpTrade.sqrtPerp.amount != 0) {
                    controller.tradePerp(
                        vaultId, WETH_ASSET_ID, getTradeParams(-perpTrade.perp.amount, -perpTrade.sqrtPerp.amount)
                    );
                }
            }

            controller.updateMargin(-controller.getVault(vaultId).margin, 0);
        }

        {
            vm.prank(user2);
            DataType.Vault memory lpVault = controller.getVault(lpVaultId);
            for (uint256 i; i < lpVault.openPositions.length; i++) {
                Perp.UserStatus memory perpTrade = lpVault.openPositions[i];

                if (perpTrade.perp.amount != 0 || perpTrade.sqrtPerp.amount != 0) {
                    TradePerpLogic.TradeParams memory tradeParams =
                        getTradeParams(-perpTrade.perp.amount, -perpTrade.sqrtPerp.amount);

                    vm.prank(user2);
                    controller.tradePerp(lpVaultId, WETH_ASSET_ID, tradeParams);
                }
            }

            vm.prank(user2);
            int256 margin = controller.getVault(lpVaultId).margin;
            vm.prank(user2);
            controller.updateMargin(-margin, 0);
        }

        vm.prank(user2);
        controller.withdrawToken(1, 1e18, true);
        vm.prank(user2);
        controller.withdrawToken(1, 1e18, false);

        assertLt(usdc.balanceOf(address(controller)), 100);
        assertLt(weth.balanceOf(address(controller)), 100);
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradePerpLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    // cannot trade if vaultId is not existed
    function testCannotTrade_IfVaultIdIsNotExisted() public {
        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(1 * 1e8, 0);

        vm.expectRevert(bytes("V1"));
        controller.tradePerp(0, WETH_ASSET_ID, tradeParams);

        vm.expectRevert(bytes("V1"));
        controller.tradePerp(1000, WETH_ASSET_ID, tradeParams);
    }

    // cannot trade if caller is not vault owner
    function testCannotTrade_IfCallerIsNotVaultOwner() public {
        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(1 * 1e8, 0);

        vm.prank(user2);
        vm.expectRevert(bytes("V2"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // cannot open position if margin is not safe
    function testCannotTrade_IfVaultIsNotSafe() public {
        controller.updateMargin(1e6 - 1e10, 0);

        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(-10 * 1e8, 0);

        vm.expectRevert(bytes("NS"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // cannot trade delta because no available supply
    function testCannotOpenLongDelta_IfThereIsNoEnoughSupply() public {
        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(1e10, 0);

        vm.expectRevert(bytes("S0"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // deadline
    function testCannotTrade_IfTimeIsGreaterThanDeadline() public {
        TradePerpLogic.TradeParams memory tradeParams = TradePerpLogic.TradeParams(
            100, 100, getLowerSqrtPrice(WETH_ASSET_ID), getUpperSqrtPrice(WETH_ASSET_ID), block.timestamp - 1, false, ""
        );

        vm.expectRevert(bytes("T1"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    // slippage
    function testCannotTrade_IfSlippageIsTooMuch() public {
        TradePerpLogic.TradeParams memory tradeParams = TradePerpLogic.TradeParams(
            100, 100, getLowerSqrtPrice(WETH_ASSET_ID), getLowerSqrtPrice(WETH_ASSET_ID), block.timestamp, false, ""
        );

        vm.expectRevert(bytes("T2"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    function testCannotTradePerp_IfAssetIdIsZero() public {
        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(100, 0);

        vm.expectRevert(bytes("A0"));
        controller.tradePerp(vaultId, 0, tradeParams);
    }

    function testCannotTradePerp_IfAssetIdIsNotExisted() public {
        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(100, 0);

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

        assertEq(vault.margin, 9999998998);

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
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999940000);
        assertEq(vault.openPositions[0].perp.amount, 0);
        assertEq(vault.openPositions[0].perp.entryValue, 0);
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

        assertEq(vault.margin, 9999998996);
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

        (uint256 ur,,) = reader.getUtilizationRatio(WETH_ASSET_ID);

        assertEq(ur, 1e18);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999980000);
    }

    // cannot open short sqrt if there is no enough liquidity
    function testCannotOpenShortSqrt_IfNoLiquidity() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));
        vm.stopPrank();

        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(0, -2 * 1e6);

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

        assertEq(vault.margin, 9999999996);
    }

    // pay interest
    function testPayInterest() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(50 * 1e6, 0));

        vm.warp(block.timestamp + 1 days);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-50 * 1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999948272);
    }

    function testPayPremium() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));
        vm.stopPrank();
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(50 * 1e6, -50 * 1e6));

        manipulateVol(50);
        vm.warp(block.timestamp + 1 hours);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-50 * 1e6, 50 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999830000);

        withdrawAll();
    }

    function testPayPremiumWithFullUtilization() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));
        vm.stopPrank();
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        manipulateVol(50);
        vm.warp(block.timestamp + 1 hours);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999420000);

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

        assertEq(vault.margin, 10098052535);

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

        assertEq(vault.margin, 10000190794);
    }

    function testShortDeltaAndPriceBecomesHigh() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-10 * 1e6, 0));

        uniswapPool.swap(address(this), false, 5 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 99);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(10 * 1e6, 0));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999889746);
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

        assertEq(vault.openPositions.length, 0);

        assertEq(vault.margin, 10000189893);

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

        assertEq(vault.margin, 9999860000);
    }

    function testShortGammaAndPriceBecomesHigh() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-10 * 1e6, 10 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 139);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(10 * 1e6, -10 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999999507);
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

        assertEq(vault.margin, 10007895971);

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

        assertEq(tradeResult.payoff.sqrtPayoff, 7998013);

        withdrawAll();
    }

    function getSqrtEntryValue(uint256 _vaultId) internal view returns (int256) {
        DataType.Vault memory vault = controller.getVault(_vaultId);
        Perp.UserStatus memory userStatus = vault.openPositions[0];

        return userStatus.sqrtPerp.entryValue; //  + userStatus.perpTrade.sqrtPerp.rebalanceEntryValue;
    }

    function testGammaAfterRebalance() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
        //address(this), true, 12 * 1e15, TickMath.MIN_SQRT_RATIO + 1, ""

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 784);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999840077);

        withdrawAll();
    }

    function testCannotTradeSqrt_IfOutOfRange() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1352);

        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(0, -100);

        vm.expectRevert(bytes("P2"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    function testSqrtOutOfRange() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1352);

        controller.reallocate(WETH_ASSET_ID);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10013924328);

        withdrawAll();
    }

    function testGammaOutOfRange() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        uniswapPool.swap(address(this), false, 7 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1352);

        controller.reallocate(WETH_ASSET_ID);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999541600);

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

        controller.reallocate(WETH_ASSET_ID);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9985890000);

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

        controller.reallocate(WETH_ASSET_ID);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10000470000);

        withdrawAll();
    }

    function testVaultValueAfterRebalance() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 784);

        vm.warp(block.timestamp + 1 hours);

        controller.reallocate(WETH_ASSET_ID);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        DataType.VaultStatusResult memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.vaultValue, 9999840124);

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

        (uint256 ur,,) = reader.getUtilizationRatio(WETH_ASSET_ID);

        assertEq(ur, 5 * 1e17);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 1 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999980000);
    }
}
